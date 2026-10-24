const { test } = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { resolve } = require("node:path");
const { runInNewContext } = require("node:vm");

const source = readFileSync(resolve(__dirname, "../../app/assets/javascripts/cbbd_membership_matches.js"), "utf8");

function fixture() {
  const listeners = {};
  const choices = ["", "1", "2"];
  const select = {
    dataset: { cbbdOptions: "schools" }, value: "1", options: ["", "1"],
    replaceChildren(options) { this.options = options; this.value = ""; },
  };
  const document = {
    documentElement: { dataset: {} },
    addEventListener(name, callback) { listeners[name] = callback; },
    getElementById(id) { return id === "schools" ? { content: { cloneNode() { return [...choices]; } } } : null; },
  };
  const event = { target: { closest() { return select.dataset.cbbdOptions ? select : null; } } };
  runInNewContext(source, { document });
  return { listeners, select, event };
}

for (const interaction of ["focusin", "pointerdown"]) {
  test(`${interaction} makes overrides available without losing the preselected match`, () => {
    const { listeners, select, event } = fixture();
    listeners[interaction](event);
    assert.deepEqual(select.options, ["", "1", "2"]);
    assert.equal(select.value, "1");
    select.value = "2";
    listeners[interaction](event);
    assert.equal(select.value, "2");
  });
}

test("unrelated controls and absent templates do not replace selections", () => {
  const { listeners, select } = fixture();
  listeners.focusin({ target: { closest() { return null; } } });
  select.dataset.cbbdOptions = "absent";
  listeners.pointerdown({ target: { closest() { return select; } } });
  assert.deepEqual(select.options, ["", "1"]);
  assert.equal(select.value, "1");
});
