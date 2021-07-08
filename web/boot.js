// out of index.html so script-src can stay 'self' with no inline allowance

// take the splash down once Flutter has painted
window.addEventListener('flutter-first-frame', function () {
  var boot = document.getElementById('boot');
  if (!boot) return;
  boot.style.opacity = '0';
  window.setTimeout(function () {
    boot.remove();
  }, 220);
});
