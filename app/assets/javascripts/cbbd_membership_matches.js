(() => {
  if (document.documentElement.dataset.cbbdMatchesBound) return;
  document.documentElement.dataset.cbbdMatchesBound = "true";

  const expandChoices = (event) => {
    const select = event.target.closest("select[data-cbbd-options]");
    if (!select) return;
    const template = document.getElementById(select.dataset.cbbdOptions);
    if (!template) return;

    const selected = select.value;
    select.replaceChildren(template.content.cloneNode(true));
    select.value = selected;
    delete select.dataset.cbbdOptions;
  };

  document.addEventListener("focusin", expandChoices);
  document.addEventListener("pointerdown", expandChoices);
})();
