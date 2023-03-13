---
layout: basic
---

{% assign last_bench = site.benchmarks | last %}

<!-- Headline Box -->
<div class="headline-box">

  <p>
  How is <a href="https://github.com/Shopify/yjit">YJIT's</a> speed on its <a href="https://github.com/Shopify/yjit-bench">benchmarks</a> as of <strong>  {{last_bench.date_str}} {{last_bench.time_str}}</strong>?
  </p>

  <span style="font-weight: bold; font-size: 125%">{% include {{ last_bench.reports.blog_speed_headline_html }} %}</span>

  {% for platform in last_bench.platforms %}
  <div class="headline-button">
    <a href="{{ last_bench.url | relative_url }}#{{platform}}"><button>Latest Full Details ({{platform}})</button></a>
  </div>
  {% endfor %}
</div>

<!-- Latest Headlining Results -->
<div class="latest-details-box">
  <h2 style="text-align: center;">Latest Headlining Results vs CRuby</h2>

  <p style="text-align: center;">
    "Overall" in the headline means results on these benchmarks. Click through for more benchmarks.
  </p>

  <div style="text-align: center;">
    <a href="{{ last_bench.url | relative_url }}"><button>Latest Full Details</button></a>
  </div>

  <div style="text-align: center;">
  <a href="{{ last_bench.url | relative_url }}">
  {% include {{last_bench.reports.blog_speed_details_x86_64_head_svg}} %}
  </a>
  Speed of each Ruby implementation (iterations/second) relative to the CRuby interpreter. Higher is better.
  </div>
</div>

<!-- Timeline Graph -->
<div class="timeline-graph-box">
  <h2 style="text-align: center;">YJIT Results Over Time</h2>

  <div style="text-align: center;">
    <a href="{{ "timeline-deep#activerecord+liquid-render+optcarrot+railsbench" | relative_url }}"><button>Results-Over-Time Deep Dive</button></a>
  </div>

  <div class="timeline_report">
  {% include reports/mini_timelines.html %}
  </div>
</div>

<!-- Stats Timeline -->
<div class="stats-timeline-report">
  <div style="text-align: center; margin-top: 3em;">
    <a href="{{ "stats-timeline#yjit_speedup+overall-mean+activerecord+liquid-render+optcarrot+railsbench" | relative_url }}"><button>YJIT Speedup and Statistics Over Time</button></a>
  </div>
</div>

<!-- Memory Usage Timeline -->

<div class="memory-timeline-report">
  <div style="text-align: center; margin-top: 3em;">
    <a href="{{ "memory_timeline#railsbench" | relative_url }}"><button>YJIT vs CRuby Memory Usage Over Time</button></a>
  </div>
</div>

<p style="text-align: center; margin-top: 3em;">
  Do you love extensive details? <br/>
  <a href="{{ "history" | relative_url }}"> <button>See All the Benchmark History</button></a>
</p>
