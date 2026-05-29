/* MemexLab Showcase — on-site submission form.
   Posts to /api/submit-case (Vercel serverless), which opens a PR against
   cases.json. Degrades gracefully: if the API isn't available (e.g. on a
   static host without functions), it points the user to the GitHub fallbacks. */
(function () {
  "use strict";

  var form = document.getElementById("case-form");
  if (!form) return;
  var statusEl = document.getElementById("form-status");
  var submitBtn = document.getElementById("case-submit");
  var siteKey = form.getAttribute("data-sitekey") || "";

  // Optionally load Cloudflare Turnstile if a real site key is configured.
  var turnstileWidgetId = null;
  if (siteKey) {
    var slot = document.getElementById("turnstile-slot");
    var s = document.createElement("script");
    s.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";
    s.async = true;
    s.defer = true;
    s.onload = function () {
      if (window.turnstile && slot) {
        turnstileWidgetId = window.turnstile.render(slot, { sitekey: siteKey });
      }
    };
    document.head.appendChild(s);
  }

  function setStatus(msg, kind) {
    statusEl.textContent = msg;
    statusEl.className = "form-status" + (kind ? " form-status--" + kind : "");
  }

  function turnstileToken() {
    if (siteKey && window.turnstile && turnstileWidgetId != null) {
      try { return window.turnstile.getResponse(turnstileWidgetId); } catch (e) { return ""; }
    }
    return "";
  }

  form.addEventListener("submit", function (e) {
    e.preventDefault();

    if (!form.checkValidity()) {
      setStatus("Please fill in the required fields.", "error");
      form.reportValidity();
      return;
    }

    var payload = {
      title: form.title.value,
      author: form.author.value,
      url: form.url.value,
      country: form.country.value,
      region: form.region.value,
      categories: form.categories.value,
      summary: form.summary.value,
      company: form.company.value, // honeypot
      turnstileToken: turnstileToken(),
    };

    submitBtn.disabled = true;
    setStatus("Submitting…", "pending");

    fetch("/api/submit-case", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    })
      .then(function (r) {
        return r.json().then(function (data) { return { ok: r.ok, status: r.status, data: data }; });
      })
      .then(function (res) {
        if (res.ok && res.data && res.data.ok) {
          form.reset();
          if (res.data.prUrl) {
            statusEl.innerHTML = "";
            var span = document.createElement("span");
            span.textContent = "Thanks! Your case was submitted as a pull request for review: ";
            var a = document.createElement("a");
            a.href = res.data.prUrl;
            a.target = "_blank";
            a.rel = "noopener noreferrer";
            a.textContent = "PR #" + (res.data.prNumber || "");
            statusEl.appendChild(span);
            statusEl.appendChild(a);
            statusEl.className = "form-status form-status--ok";
          } else {
            setStatus("Thanks! Your submission was received.", "ok");
          }
        } else {
          var msg = (res.data && res.data.error) || ("Submission failed (" + res.status + ").");
          setStatus(msg + " You can also use the GitHub fallbacks below.", "error");
        }
      })
      .catch(function () {
        setStatus("The submission service isn’t reachable here. Please use the GitHub issue form or edit cases.json below.", "error");
      })
      .then(function () {
        submitBtn.disabled = false;
        if (siteKey && window.turnstile && turnstileWidgetId != null) {
          try { window.turnstile.reset(turnstileWidgetId); } catch (e) {}
        }
      });
  });
})();
