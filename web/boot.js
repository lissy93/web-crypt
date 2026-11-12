// out of index.html so script-src can stay 'self' with no inline allowance

// a theme picked in settings beats the system one, so the splash matches it
try {
  var theme = JSON.parse(localStorage.getItem('flutter.theme'));
  if (theme === 'light' || theme === 'dark') {
    document.documentElement.style.colorScheme = theme;
    document.querySelectorAll('meta[name="theme-color"]').forEach(function (m) {
      m.removeAttribute('media');
      m.content = theme === 'dark' ? '#191a19' : '#fbfbfa';
    });
  }
} catch (_) {}

// take the splash down once Flutter has painted
window.addEventListener('flutter-first-frame', function () {
  var boot = document.getElementById('boot');
  if (!boot) return;
  boot.style.opacity = '0';
  window.setTimeout(function () {
    boot.remove();
  }, 220);
});
