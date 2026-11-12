import { defineConfig } from 'vite';
import { viteSingleFile } from 'vite-plugin-singlefile';
import pkg from './package.json' with { type: 'json' };

// 产物是单个 index.html：JS、CSS、音效全部内联，双击即可玩
export default defineConfig({
  plugins: [viteSingleFile()],
  // .glb 当成静态资源处理，?url 导入会在 assetsInlineLimit 内自动内联成 data URL
  assetsInclude: ['**/*.glb'],
  // 版本号只在 package.json 里改一次
  define: { __APP_VERSION__: JSON.stringify(pkg.version) },
  build: {
    target: 'es2020',
    cssCodeSplit: false,
    assetsInlineLimit: 64 * 1024 * 1024,
    rollupOptions: { output: { inlineDynamicImports: true } },
  },
});
