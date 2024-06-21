function showSVGTooltip(evt, text) {
  let tt = document.getElementById("svg_tooltip");
  if(tt === null) return;
  tt.innerHTML = text;
  tt.style.display = "block";
  tt.style.left = evt.pageX + 10 + 'px';
  tt.style.top = evt.pageY + 10 + 'px';
}

function hideSVGTooltip() {
  var tt = document.getElementById("svg_tooltip");
  if(tt === undefined) return;
  tt.style.display = "none";
}

var fadeCount = 0;
function fadeOutEffect(fadeTarget) {
  fadeCount++;
  var currentFadeCount = fadeCount;

  fadeTarget.opacity = 1;
  fadeTarget.display = 'block';

  var fadeEffect = setInterval(function () {
    // Another fade happening? Cancel the older fade.
    if (fadeCount != currentFadeCount) {
      clearInterval(fadeEffect);
      return;
    }
    if (!fadeTarget.style.opacity) {
      fadeTarget.style.opacity = 1;
    }
    if (fadeTarget.style.opacity > 0) {
      fadeTarget.style.opacity -= 0.1;
    } else {
      fadeTarget.style.display = 'none';
      fadeTarget.style.opacity = 1.0;
      clearInterval(fadeEffect);
    }
  }, 200);
}

function showCopyConfirm(e) {
  var copied_confirm = document.getElementById("svg_tooltip_sha_copied");
  if(copied_confirm === undefined) return;

  hideSVGTooltip();

  //console.log(e.trigger);
  var rect = e.trigger.getBoundingClientRect();
  //console.log("Rect", rect.top, rect.right, rect.bottom, rect.left);
  //console.log("Scroll", window.scrollX, window.scrollY);

  // This is completely failing to work, and I have no idea why. D'oh.
  copied_confirm.innerHTML = "Copied SHA to clipboard: " + e.text;
  copied_confirm.style.left = rect.left + window.scrollX;
  copied_confirm.style.top = rect.top + window.scrollY;
  copied_confirm.display = 'block';
  copied_confirm.opacity = 1;
  fadeOutEffect(copied_confirm);
}

// Show and hide tooltips on graphs
// TODO: track *which* tooltip-enabled object popped this up, and do more intelligent show/hide rather than constant
// flicker as we transition over object after object...
document.addEventListener("mousemove", function (e) {
  if(!e.target.matches('svg [data-tooltip]')) return;
  showSVGTooltip(e, e.target.getAttribute("data-tooltip"));
});
document.addEventListener("mouseout", function (e) {
  if(!e.target.matches('svg [data-tooltip]')) return;
  hideSVGTooltip();
});

var clipboard = new ClipboardJS('[data-clipboard-text]');
clipboard.on("success", function(e) {
  console.log("Copied to clipboard: " + e.text);
  showCopyConfirm(e);
  e.clearSelection();
});
clipboard.on('error', function(e) {
  console.error('Failed copying SHA to clipboard on click');
  console.error('Action:', e.action);
  console.error('Trigger:', e.trigger);
});

// Find UTC timestamps on the page and change them to browser local time.
function convertTimeStampsToLocal() {
  // Use en-CA to get YYYY-MM-DD style.
  var fmt = new Intl.DateTimeFormat('en-CA', {
    hour: "numeric",
    minute: "numeric",
    second: "numeric",
    day: "numeric",
    year: "numeric",
    month: "numeric",
    hour12: false,
    // timeZoneName: "short" => "MST", "shortOffset" => "GMT - 7"
    timeZoneName: "shortOffset",
  });
  document.querySelectorAll('.timestamp').forEach(function(el) {
    var ts = el.innerText;
    el.title = (el.title || '') + ts;
    el.innerText = fmt.format(new Date(ts)).replace(/,/, '');
  });
}
convertTimeStampsToLocal();
