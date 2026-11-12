import * as THREE from 'three';
import { makeNumberTexture, makeFlagTexture, makeQuestionTexture } from './geometry.js';
import { loadCubeGeometry } from './cube-model.js';
import { Board, HIDDEN, REVEALED, FLAGGED, QUESTION } from './logic.js';

// 立方体边长与收缩比例，和 Godot 版保持一致
export const HIDDEN_SIZE = 0.88;
export const REVEALED_SIZE = 0.70;
// 格距超过这个值，方块之间的缝隙已经宽到能看见所有面
export const OPEN_VIEW_PITCH = 1.15;

const COLORS = {
  hidden: 0xe0e5ee,
  flag: 0xe0cda4,
  question: 0xb4bdcd,
  open: 0x363f50,
  mine: 0xa32832,
  hit: 0xff5151,
};

// 面的顺序 +Z -Z +X -X +Y -Y，与 logic.js 的 FACE_AXIS 对齐
const FACE_NORMALS = [
  [0, 0, 1], [0, 0, -1],
  [1, 0, 0], [-1, 0, 0],
  [0, 1, 0], [0, -1, 0],
];

const DIRS = [
  [0, 0, 1], [0, 0, -1],
  [1, 0, 0], [-1, 0, 0],
  [0, 1, 0], [0, -1, 0],
];

export function faceFromNormal(n) {
  const ax = Math.abs(n.x);
  const ay = Math.abs(n.y);
  const az = Math.abs(n.z);
  if (az >= ax && az >= ay) return n.z > 0 ? 0 : 1;
  if (ax >= ay) return n.x > 0 ? 2 : 3;
  return n.y > 0 ? 4 : 5;
}

export class World {
  constructor(canvas) {
    this.canvas = canvas;
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false });
    this.renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
    this.renderer.setClearColor(0xc8cfdd);

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(42, 1, 0.1, 400);

    // 相机：球坐标绕 pivot 转，pivot 可平移
    this.yaw = 38;
    this.pitch = 34;
    this.distance = 8;
    this.pivot = new THREE.Vector3();

    this.scene.add(new THREE.AmbientLight(0xb8c2dd, 1.15));
    const key = new THREE.DirectionalLight(0xffffff, 2.1);
    key.position.set(-6, 12, 8);
    this.scene.add(key);
    const fill = new THREE.DirectionalLight(0xc6d6ff, 0.7);
    fill.position.set(8, -4, -9);
    this.scene.add(fill);

    this.cubeGeo = loadCubeGeometry();
    this.faceGeo = new THREE.PlaneGeometry(1, 1);

    this.materials = {
      hidden: new THREE.MeshStandardMaterial({ color: COLORS.hidden, roughness: 0.62, metalness: 0 }),
      flag: new THREE.MeshStandardMaterial({ color: COLORS.flag, roughness: 0.78, metalness: 0 }),
      question: new THREE.MeshStandardMaterial({ color: COLORS.question, roughness: 0.78, metalness: 0 }),
      open: new THREE.MeshStandardMaterial({ color: COLORS.open, roughness: 0.55, metalness: 0 }),
      mine: new THREE.MeshStandardMaterial({ color: COLORS.mine, roughness: 0.45, metalness: 0 }),
      hit: new THREE.MeshStandardMaterial({ color: COLORS.hit, roughness: 0.4, emissive: 0xff2222, emissiveIntensity: 0.35 }),
    };

    this.numberMats = [];
    for (let n = 1; n <= 9; n++) {
      this.numberMats[n] = new THREE.MeshBasicMaterial({
        map: makeNumberTexture(n), transparent: true, depthWrite: false,
      });
    }
    this.flagMat = new THREE.MeshBasicMaterial({ map: makeFlagTexture(), transparent: true, depthWrite: false });
    this.questionMat = new THREE.MeshBasicMaterial({ map: makeQuestionTexture(), transparent: true, depthWrite: false });

    this.group = new THREE.Group();
    this.scene.add(this.group);

    this.cells = [];
    this.meshes = [];
    this.pitch = 1;
    this.openView = false;
    this.dirtyFacing = true;

    this._resize();
  }

  _resize() {
    const w = this.canvas.clientWidth || 1;
    const h = this.canvas.clientHeight || 1;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  }

  resize() {
    this._resize();
    this.dirtyFacing = true;
  }

  /* ---------------- 相机 ---------------- */

  applyCamera() {
    const y = (this.yaw * Math.PI) / 180;
    const p = (this.pitch * Math.PI) / 180;
    const dir = new THREE.Vector3(Math.cos(p) * Math.sin(y), Math.sin(p), Math.cos(p) * Math.cos(y));
    this.camera.position.copy(this.pivot).addScaledVector(dir, this.distance);
    this.camera.lookAt(this.pivot);
    this.dirtyFacing = true;
  }

  frame(side) {
    this.pivot.set(0, 0, 0);
    this.distance = Math.min(Math.max(side * 2.7, 6), 44);
    this.applyCamera();
  }

  orbit(dx, dy) {
    this.yaw -= dx * 0.32;
    this.pitch = Math.min(86, Math.max(-86, this.pitch + dy * 0.32));
    this.applyCamera();
  }

  pan(dx, dy) {
    const scale = this.distance * 0.0016;
    const right = new THREE.Vector3().setFromMatrixColumn(this.camera.matrix, 0);
    const up = new THREE.Vector3().setFromMatrixColumn(this.camera.matrix, 1);
    this.pivot.addScaledVector(right, -dx * scale).addScaledVector(up, dy * scale);
    this.applyCamera();
  }

  zoom(delta) {
    this.distance = Math.min(Math.max(this.distance + delta, 3), 90);
    this.applyCamera();
  }

  /* ---------------- 盘面 ---------------- */

  build(board, pitch) {
    this.board = board;
    this.pitch = pitch;
    this.openView = pitch >= OPEN_VIEW_PITCH;

    for (const cell of this.cells) this.group.remove(cell.root);
    this.cells = [];
    this.meshes = [];

    const n = board.side;
    const offset = ((n - 1) * pitch) / 2;

    for (let z = 0; z < n; z++) {
      for (let y = 0; y < n; y++) {
        for (let x = 0; x < n; x++) {
          const i = board.index(x, y, z);
          const cell = this._makeCell(i);
          cell.root.position.set(x * pitch - offset, y * pitch - offset, z * pitch - offset);
          cell.coord = [x, y, z];
          this.group.add(cell.root);
          this.cells[i] = cell;
          this.meshes.push(cell.cube);
          this._applyCell(i);
        }
      }
    }
    this.dirtyFacing = true;
  }

  /** 每个面片一份材质：透明度、贴图都逐片控制 */
  _faceMaterial() {
    return new THREE.MeshBasicMaterial({ transparent: true, depthWrite: false });
  }

  _makeCell(i) {
    const root = new THREE.Group();

    const cube = new THREE.Mesh(this.cubeGeo, this.materials.hidden);
    cube.userData.cellIndex = i;
    root.add(cube);

    const faces = [];
    const marks = [];
    for (let f = 0; f < 6; f++) {
      const nrm = new THREE.Vector3(...FACE_NORMALS[f]);
      const sign = new THREE.Mesh(this.faceGeo, this._faceMaterial());
      sign.rotation.x = f === 4 ? -Math.PI / 2 : f === 5 ? Math.PI / 2 : 0;
      sign.rotation.y = f === 0 ? 0 : f === 1 ? Math.PI : f === 2 ? Math.PI / 2 : f === 3 ? -Math.PI / 2 : 0;
      sign.visible = false;
      root.add(sign);
      faces.push(sign);

      const mark = new THREE.Mesh(this.faceGeo, this._faceMaterial());
      mark.rotation.copy(sign.rotation);
      mark.visible = false;
      root.add(mark);
      marks.push(mark);
    }

    return { root, cube, faces, marks, sign: 0, mask: 0, planes: new Array(6).fill(null) };
  }

  /** 相邻格是否已揭示（决定哪些面朝外可见） */
  faceMask(i) {
    if (this.openView) return 63;
    const board = this.board;
    const [x, y, z] = board.coord(i);
    let mask = 0;
    for (let f = 0; f < 6; f++) {
      const [dx, dy, dz] = DIRS[f];
      const nx = x + dx;
      const ny = y + dy;
      const nz = z + dz;
      if (!board.inBounds(nx, ny, nz)) {
        mask |= 1 << f;
      } else if (board.states[board.index(nx, ny, nz)] === REVEALED) {
        mask |= 1 << f;
      }
    }
    return mask;
  }

  _applyCell(i) {
    const board = this.board;
    const cell = this.cells[i];
    const state = board.states[i];
    const cube = cell.cube;

    for (const f of cell.faces) f.visible = false;
    for (const m of cell.marks) m.visible = false;
    cell.mask = 0;
    cell.planes.fill(null);

    if (state === FLAGGED || state === QUESTION) {
      const size = REVEALED_SIZE;
      cube.material = state === FLAGGED ? this.materials.flag : this.materials.question;
      cube.scale.setScalar(size);
      const mask = this.faceMask(i);
      const mat = state === FLAGGED ? this.flagMat : this.questionMat;
      for (let f = 0; f < 6; f++) {
        if (!(mask & (1 << f))) continue;
        const m = cell.marks[f];
        if (m.material.map !== mat.map) {
          m.material.map = mat.map;
          m.material.needsUpdate = true;
        }
        m.material.opacity = 1;
        m.scale.setScalar(size * 0.5);
        m.position.copy(new THREE.Vector3(...FACE_NORMALS[f]).multiplyScalar(size * 0.5 + 0.004));
        m.visible = true;
      }
      cell.mask = mask;
      return;
    }

    if (state !== REVEALED) {
      cube.material = this.materials.hidden;
      cube.scale.setScalar(HIDDEN_SIZE);
      cube.visible = true;
      cell.sign = 0;
      return;
    }

    // 已揭示：任一面有数字才留下方块，全 0 的整颗消失
    const fc = board.faceCountsOf(i);
    let has = 0;
    for (const v of fc) has = Math.max(has, v);

    if (has === 0) {
      cube.visible = false;
      cell.sign = 0;
      return;
    }

    cube.visible = true;
    cube.material = this.materials.open;
    cube.scale.setScalar(REVEALED_SIZE);

    const mask = this.faceMask(i);
    for (let f = 0; f < 6; f++) {
      if (!(mask & (1 << f))) continue;
      if (fc[f] <= 0) continue;
      const sign = cell.faces[f];
      const tex = this.numberMats[Math.min(fc[f], 9)].map;
      if (sign.material.map !== tex) {
        sign.material.map = tex;
        sign.material.needsUpdate = true;
      }
      sign.material.opacity = 1;
      sign.scale.setScalar(REVEALED_SIZE * 0.56);
      sign.position.copy(new THREE.Vector3(...FACE_NORMALS[f]).multiplyScalar(REVEALED_SIZE * 0.5 + 0.004));
      sign.visible = true;
      cell.planes[f] = sign;
    }
    cell.mask = mask;
    cell.sign = 1;
  }

  /** 界面状态变化后重画单格 */
  refresh(i) {
    this._applyCell(i);
    this.dirtyFacing = true;
  }

  refreshArea(indices) {
    const seen = new Set();
    for (const i of indices) {
      for (const n of [i, ...this.board.neighbors(i)]) seen.add(n);
    }
    for (const i of seen) this._applyCell(i);
    this.dirtyFacing = true;
  }

  markMines() {
    const board = this.board;
    for (const i of board.mineIndices()) {
      const cell = this.cells[i];
      if (!cell) continue;
      if (board.states[i] === FLAGGED) continue;
      cell.cube.visible = true;
      cell.cube.material = i === board.hitIndex ? this.materials.hit : this.materials.mine;
      cell.cube.scale.setScalar(i === board.hitIndex ? 0.78 : 0.66);
      for (const f of cell.faces) f.visible = false;
      for (const m of cell.marks) m.visible = false;
      cell.planes.fill(null);
    }
    this.dirtyFacing = true;
  }

  /** 间距只挪位置，方块尺寸不变 */
  relayout(pitch) {
    this.pitch = pitch;
    const wasOpen = this.openView;
    this.openView = pitch >= OPEN_VIEW_PITCH;
    const board = this.board;
    if (!board) return;
    const n = board.side;
    const offset = ((n - 1) * pitch) / 2;
    for (let i = 0; i < this.cells.length; i++) {
      const cell = this.cells[i];
      if (!cell) continue;
      const [x, y, z] = cell.coord;
      cell.root.position.set(x * pitch - offset, y * pitch - offset, z * pitch - offset);
    }
    // 可见面集合变了才需要重画数字
    if (wasOpen !== this.openView) {
      for (let i = 0; i < this.cells.length; i++) if (this.cells[i]) this._applyCell(i);
    }
    this.dirtyFacing = true;
  }

  /** 掠射角上的面淡出，否则「1」会被压成别的形状 */
  updateFacing() {
    if (!this.dirtyFacing) return;
    this.dirtyFacing = false;
    const cam = this.camera.position;
    const half = REVEALED_SIZE * 0.5;
    for (const cell of this.cells) {
      if (!cell) continue;
      for (let f = 0; f < 6; f++) {
        const target = cell.planes[f];
        if (!target) continue;
        const n = new THREE.Vector3(...FACE_NORMALS[f]);
        const center = cell.root.position.clone().addScaledVector(n, half);
        const toCam = cam.clone().sub(center).normalize();
        const alpha = Math.min(1, Math.max(0, (n.dot(toCam) - 0.26) / 0.14));
        target.material.opacity = alpha;
        target.visible = alpha > 0.02;
      }
    }
  }

  /** 屏幕坐标 → { index, face } */
  pick(px, py) {
    const rect = this.canvas.getBoundingClientRect();
    const ndc = new THREE.Vector2(
      ((px - rect.left) / rect.width) * 2 - 1,
      -((py - rect.top) / rect.height) * 2 + 1
    );
    const ray = new THREE.Raycaster();
    ray.setFromCamera(ndc, this.camera);
    const hits = ray.intersectObjects(this.meshes, false);
    for (const hit of hits) {
      if (!hit.object.visible) continue;
      const idx = hit.object.userData.cellIndex;
      const n = hit.face ? hit.face.normal : new THREE.Vector3(0, 1, 0);
      return { index: idx, face: faceFromNormal(n), point: hit.point };
    }
    return null;
  }

  render() {
    this.updateFacing();
    this.renderer.render(this.scene, this.camera);
  }
}
