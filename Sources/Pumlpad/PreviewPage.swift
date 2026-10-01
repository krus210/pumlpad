import CryptoKit
import Foundation

/// The preview page: a scrollable stage for the SVG plus zoom and pan handling.
enum PreviewPage {
    /// Only this page's script runs: it is allowed by its hash, so inline handlers and
    /// `javascript:` links inside a diagram are not. Images must be embedded; nothing is fetched.
    static let html: String = {
        let scriptHash = Data(SHA256.hash(data: Data(script.utf8))).base64EncodedString()
        let policy = [
            "default-src 'none'",
            "script-src 'sha256-\(scriptHash)'",
            // PlantUML styles its SVG with `style` attributes and `<style>` elements.
            "style-src 'unsafe-inline'",
            "img-src data:",
        ].joined(separator: "; ")
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(policy)">
        <style>\(style)</style>
        </head>
        <body>
        <div id="viewport"><div id="stage"></div></div>
        <div id="message">Starting PlantUML…</div>
        <script>\(script)</script>
        </body>
        </html>
        """
    }()

    private static let style = """
    :root { --paper: #ffffff; --ink: #6e6e73; }
    :root.dark { --paper: #1e1e1e; --ink: #98989d; }
    html, body { margin: 0; height: 100%; overflow: hidden; background: var(--paper);
                 font: 13px -apple-system, BlinkMacSystemFont, sans-serif; }
    #viewport { position: absolute; inset: 0; overflow: auto; cursor: grab; }
    #viewport.panning { cursor: grabbing; }
    #stage { display: flex; justify-content: center; align-items: flex-start; box-sizing: border-box;
             width: max-content; min-width: 100%; min-height: 100%; padding: 24px; }
    #stage svg { flex: none; display: block; }
    #stage.stale svg { opacity: 0.35; filter: grayscale(0.7); transition: opacity 0.15s; }
    #message { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;
               padding: 32px; color: var(--ink); white-space: pre-wrap; text-align: center; line-height: 1.5; }
    [hidden] { display: none !important; }
    """

    private static let script = """
    (() => {
      const viewport = document.getElementById('viewport');
      const stage = document.getElementById('stage');
      const message = document.getElementById('message');
      const PADDING = 24;
      let zoom = 1;
      let natural = null;
      let fitted = false;

      const post = (body) => window.webkit.messageHandlers.pumlpad.postMessage(body);
      const svgElement = () => stage.querySelector('svg');

      function naturalSize(svg) {
        const box = svg.viewBox && svg.viewBox.baseVal;
        if (box && box.width > 0 && box.height > 0) return { w: box.width, h: box.height };
        return { w: parseFloat(svg.getAttribute('width')) || 300, h: parseFloat(svg.getAttribute('height')) || 150 };
      }

      function apply() {
        const svg = svgElement();
        if (!svg || !natural) return;
        svg.style.width = natural.w * zoom + 'px';
        svg.style.height = natural.h * zoom + 'px';
        post({ zoom });
      }

      // Zooms keeping the diagram point under (x, y) in place.
      function setZoom(value, x, y) {
        const svg = svgElement();
        if (!svg || !natural) return;
        const cx = x ?? viewport.clientWidth / 2;
        const cy = y ?? viewport.clientHeight / 2;
        const before = svg.getBoundingClientRect();
        const px = (cx - before.left) / zoom;
        const py = (cy - before.top) / zoom;
        zoom = Math.min(8, Math.max(0.05, value));
        apply();
        const after = svg.getBoundingClientRect();
        viewport.scrollLeft += after.left + px * zoom - cx;
        viewport.scrollTop += after.top + py * zoom - cy;
      }

      function fit(allowEnlarge) {
        if (!natural) return;
        const scale = Math.min(
          (viewport.clientWidth - PADDING * 2) / natural.w,
          (viewport.clientHeight - PADDING * 2) / natural.h
        );
        zoom = Math.max(0.05, allowEnlarge ? scale : Math.min(1, scale));
        apply();
        viewport.scrollLeft = 0;
        viewport.scrollTop = 0;
      }

      window.pumlpad = {
        setSVG(markup) {
          const left = viewport.scrollLeft;
          const top = viewport.scrollTop;
          stage.innerHTML = markup;
          stage.classList.remove('stale');
          message.hidden = true;
          viewport.hidden = false;
          const svg = svgElement();
          if (!svg) return;
          natural = naturalSize(svg);
          // The first picture of a document fits the window; later ones keep zoom and scroll.
          if (!fitted) {
            fitted = true;
            fit(false);
          } else {
            apply();
            viewport.scrollLeft = left;
            viewport.scrollTop = top;
          }
        },
        setStale(stale) { stage.classList.toggle('stale', !!stale); },
        showMessage(text) {
          message.textContent = text;
          message.hidden = false;
          viewport.hidden = true;
          stage.innerHTML = '';
          natural = null;
          fitted = false;
        },
        setDark(dark) { document.documentElement.classList.toggle('dark', !!dark); },
        zoomIn() { setZoom(zoom * 1.25); },
        zoomOut() { setZoom(zoom / 1.25); },
        actualSize() { setZoom(1); },
        fit() { fit(true); },
      };

      // Trackpad pinch arrives as WebKit gesture events.
      let gestureStart = 1;
      viewport.addEventListener('gesturestart', (event) => { event.preventDefault(); gestureStart = zoom; });
      viewport.addEventListener('gesturechange', (event) => {
        event.preventDefault();
        setZoom(gestureStart * event.scale, event.clientX, event.clientY);
      });
      viewport.addEventListener('wheel', (event) => {
        if (!event.ctrlKey && !event.metaKey) return;
        event.preventDefault();
        setZoom(zoom * Math.exp(-event.deltaY / 300), event.clientX, event.clientY);
      }, { passive: false });

      // Drag pans; Option-drag selects text instead.
      let drag = null;
      viewport.addEventListener('mousedown', (event) => {
        if (event.button !== 0 || event.altKey) return;
        drag = { x: event.clientX, y: event.clientY, left: viewport.scrollLeft, top: viewport.scrollTop };
        viewport.classList.add('panning');
        event.preventDefault();
      });
      window.addEventListener('mousemove', (event) => {
        if (!drag) return;
        viewport.scrollLeft = drag.left - (event.clientX - drag.x);
        viewport.scrollTop = drag.top - (event.clientY - drag.y);
      });
      window.addEventListener('mouseup', () => {
        drag = null;
        viewport.classList.remove('panning');
      });
    })();
    """
}
