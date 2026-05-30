/* MemexLab Showcase — loads cases.json, builds filters, renders cards.
   Vanilla JS, no dependencies. Static-host friendly. */
(function () {
  "use strict";

  var grid = document.getElementById("case-grid");
  var countEl = document.getElementById("result-count");
  var emptyEl = document.getElementById("empty-state");
  var errorEl = document.getElementById("error-state");
  var exampleNote = document.getElementById("example-note");
  var searchEl = document.getElementById("search");
  var regionGroup = document.querySelector('[data-filter="region"]');
  var catGroup = document.querySelector('[data-filter="category"]');

  var allCases = [];
  var filters = { region: "All", category: "All", q: "" };

  function text(s) {
    return String(s == null ? "" : s);
  }

  // Build the set of filter values present in the data.
  function uniqueValues(cases, key) {
    var set = {};
    cases.forEach(function (c) {
      var v = c[key];
      if (Array.isArray(v)) {
        v.forEach(function (x) { if (x) set[x] = true; });
      } else if (v) {
        set[v] = true;
      }
    });
    return Object.keys(set).sort();
  }

  function buildChips(group, values, kind) {
    var items = ["All"].concat(values);
    group.innerHTML = "";
    items.forEach(function (val) {
      var btn = document.createElement("button");
      btn.type = "button";
      btn.className = "chip";
      btn.textContent = val;
      btn.setAttribute("aria-pressed", val === "All" ? "true" : "false");
      if (val === "All") btn.classList.add("chip--on");
      btn.addEventListener("click", function () {
        filters[kind] = val;
        // visually mark selected chip within this group
        Array.prototype.forEach.call(group.children, function (child) {
          var on = child === btn;
          child.classList.toggle("chip--on", on);
          child.setAttribute("aria-pressed", on ? "true" : "false");
        });
        render();
      });
      group.appendChild(btn);
    });
  }

  function matches(c) {
    if (filters.region !== "All" && c.region !== filters.region) return false;
    if (filters.category !== "All") {
      var cats = Array.isArray(c.categories) ? c.categories : [];
      if (cats.indexOf(filters.category) === -1) return false;
    }
    if (filters.q) {
      var hay = (text(c.title) + " " + text(c.author) + " " + text(c.summary) + " " +
        text(c.country) + " " + (c.categories || []).join(" ")).toLowerCase();
      if (hay.indexOf(filters.q) === -1) return false;
    }
    return true;
  }

  function cardEl(c) {
    var li = document.createElement("li");
    li.className = "case-card";

    var head = document.createElement("div");
    head.className = "case-head";

    var place = document.createElement("span");
    place.className = "case-place";
    place.textContent = (c.flag ? c.flag + " " : "") + text(c.country || c.region || "");
    head.appendChild(place);

    if (c.example) {
      var ex = document.createElement("span");
      ex.className = "case-example";
      ex.textContent = "Example";
      head.appendChild(ex);
    }
    li.appendChild(head);

    var h3 = document.createElement("h3");
    h3.className = "case-title";
    if (c.url) {
      var a = document.createElement("a");
      a.href = c.url;
      a.rel = "noopener noreferrer";
      a.target = "_blank";
      a.textContent = text(c.title);
      h3.appendChild(a);
    } else {
      h3.textContent = text(c.title);
    }
    li.appendChild(h3);

    var meta = document.createElement("p");
    meta.className = "case-meta";
    meta.textContent = [text(c.author), text(c.date)].filter(Boolean).join(" · ");
    li.appendChild(meta);

    var summary = document.createElement("p");
    summary.className = "case-summary";
    summary.textContent = text(c.summary);
    li.appendChild(summary);

    if (Array.isArray(c.categories) && c.categories.length) {
      var tags = document.createElement("ul");
      tags.className = "case-tags";
      c.categories.forEach(function (cat) {
        var t = document.createElement("li");
        t.className = "case-tag";
        t.textContent = cat;
        tags.appendChild(t);
      });
      li.appendChild(tags);
    }
    return li;
  }

  function render() {
    var shown = allCases.filter(matches);
    grid.innerHTML = "";
    shown.forEach(function (c) { grid.appendChild(cardEl(c)); });
    emptyEl.hidden = shown.length !== 0;
    countEl.textContent =
      shown.length + (shown.length === 1 ? " case" : " cases") +
      (shown.length !== allCases.length ? " of " + allCases.length : "");
  }

  function init(data) {
    allCases = (data && Array.isArray(data.cases)) ? data.cases : [];
    buildChips(regionGroup, uniqueValues(allCases, "region"), "region");
    buildChips(catGroup, uniqueValues(allCases, "categories"), "category");
    if (allCases.some(function (c) { return c.example; })) exampleNote.hidden = false;
    searchEl.addEventListener("input", function () {
      filters.q = searchEl.value.trim().toLowerCase();
      render();
    });
    render();
  }

  fetch("./cases.json", { cache: "no-cache" })
    .then(function (r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.json();
    })
    .then(init)
    .catch(function () {
      errorEl.hidden = false;
      countEl.textContent = "";
    });
})();
