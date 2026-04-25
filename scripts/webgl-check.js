/**
 * scripts/webgl-check.js
 *
 * Paste this into Chrome DevTools console (F12 → Console tab) inside the VM
 * BEFORE installing any proctoring software.
 *
 * Reports the exact strings that Proctorio and other browser-extension-based
 * proctoring tools read when checking for VM display environments.
 *
 * Run this to confirm the WebGL renderer looks legitimate before testing.
 */

(function () {
  const results = {};

  // --- WebGL 1 renderer ---
  try {
    const canvas = document.createElement('canvas');
    const gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
    if (gl) {
      const ext = gl.getExtension('WEBGL_debug_renderer_info');
      if (ext) {
        results.webgl1_vendor   = gl.getParameter(ext.UNMASKED_VENDOR_WEBGL);
        results.webgl1_renderer = gl.getParameter(ext.UNMASKED_RENDERER_WEBGL);
      } else {
        results.webgl1_renderer = gl.getParameter(gl.RENDERER);
        results.webgl1_vendor   = gl.getParameter(gl.VENDOR);
        results.webgl1_note     = 'WEBGL_debug_renderer_info not available (extension blocked)';
      }
    }
  } catch (e) {
    results.webgl1_error = e.message;
  }

  // --- WebGL 2 renderer ---
  try {
    const canvas2 = document.createElement('canvas');
    const gl2 = canvas2.getContext('webgl2');
    if (gl2) {
      const ext2 = gl2.getExtension('WEBGL_debug_renderer_info');
      if (ext2) {
        results.webgl2_vendor   = gl2.getParameter(ext2.UNMASKED_VENDOR_WEBGL);
        results.webgl2_renderer = gl2.getParameter(ext2.UNMASKED_RENDERER_WEBGL);
      }
    }
  } catch (e) {
    results.webgl2_error = e.message;
  }

  // --- Screen info ---
  results.screen_width      = screen.width;
  results.screen_height     = screen.height;
  results.color_depth       = screen.colorDepth;
  results.pixel_ratio       = window.devicePixelRatio;
  results.hardware_concurrency = navigator.hardwareConcurrency;
  results.device_memory     = navigator.deviceMemory || 'not reported';
  results.platform          = navigator.platform;
  results.user_agent        = navigator.userAgent;

  // --- Verdict ---
  const vmStrings = [
    'VirtIO', 'Red Hat', 'SVGA', 'VMware', 'VirtualBox', 'llvmpipe',
    'SwiftShader', 'ANGLE (Vulkan', 'softpipe', 'QEMU', 'bochs'
  ];
  const renderer = (results.webgl1_renderer || '') + ' ' + (results.webgl1_vendor || '');
  const vmDetected = vmStrings.some(s => renderer.toLowerCase().includes(s.toLowerCase()));

  results.verdict = vmDetected
    ? '⚠ VM LIKELY DETECTED — renderer string contains VM identifier'
    : '✓ CLEAN — renderer string does not contain known VM identifiers';

  // --- Output ---
  console.group('%c WebGL / Environment Audit', 'font-weight:bold;font-size:14px;color:#0af');
  for (const [k, v] of Object.entries(results)) {
    const style = k === 'verdict'
      ? (vmDetected ? 'color:#f55;font-weight:bold' : 'color:#5f5;font-weight:bold')
      : 'color:#ccc';
    console.log('%c' + k.padEnd(30) + '%c' + v, 'color:#aaa', style);
  }
  console.groupEnd();

  console.log('\n--- Copy-paste for results-hardened.md ---');
  console.log(JSON.stringify(results, null, 2));

  return results;
})();
