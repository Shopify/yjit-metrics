---
layout: basic
---

{% assign last_bench = site.benchmarks | last %}

<div class="headline-box">

<p>
How is <a href="https://github.com/Shopify/yjit">YJIT's</a> speed on its <a href="https://github.com/Shopify/yjit-bench">benchmarks</a> as of <strong>{{last_bench.date_str}} {{last_bench.time_str}}</strong>?
</p>

<span style="font-weight: bold; font-size: 125%">{% include {{ last_bench.reports.blog_speed_headline_html }} %}</span>

<div class="headline-button">
  <a href="{{ last_bench.url | relative_url }}"><button>Latest Full Details</button></a>
</div>
</div>

<h2 style="text-align: center;">YJIT Results Over Time</h2>

<div style="text-align: center;">
  <a href="{{ "timeline-deep" | relative_url }}"><button>Results-Over-Time Deep Dive</button></a>
</div>

<div class="timeline_report">
{% include reports/blog_timeline.html %}
</div>

<h2 style="text-align: center;">Latest Results vs CRuby and MJIT</h2>

<div style="text-align: center;">
  <a href="{{ last_bench.url | relative_url }}"><button>Latest Full Details</button></a>
</div>

<div style="text-align: center;">
<a href="{{ last_bench.url | relative_url }}">
{% include {{last_bench.reports.blog_speed_details_head_svg}} %}
</a>
The details graphs are the speed (reqs/second) scaled to MRI's interpreted performance. Higher is better.
</div>

<p style="text-align: center; margin-top: 3em;">
  Do you love extensive details? <br/>
  <a href="{{ "history" | relative_url }}"> <button>See All the Benchmark History</button></a>
</p>

<script>
  document.querySelectorAll("svg [data-tooltip]").forEach(function (elt) {
    elt.addEventListener("mousemove", (e) => { showSVGTooltip(e, e.target.getAttribute("data-tooltip")); });
  });
  document.querySelectorAll("svg [data-tooltip]").forEach(function (elt) {
    elt.addEventListener("mouseout", (e) => { hideSVGTooltip(); });
  });
</script>
