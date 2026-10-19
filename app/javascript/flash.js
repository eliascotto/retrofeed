window.showFlash = function (message, level = "info") {
  const flashes = document.getElementById("flashes");

  if (!flashes) return;

  const el = document.createElement("div");
  el.className = `flash__item flash__item--${level}`;
  el.setAttribute("data-controller", "element-removal");
  el.setAttribute("data-action", "animationend->element-removal#remove");
  el.textContent = message;

  flashes.appendChild(el);
};
