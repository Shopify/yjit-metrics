---
layout: basic
---

{% assign last_bench = site.benchmarks | last %}

How is [YJIT's](https://github.com/Shopify/yjit) speed on its [benchmarks](https://github.com/Shopify/yjit-bench) as of <strong>{{last_bench.date_str}} {{last_bench.time_str}}</strong>?

<!-- Headlines -->
<span style="font-weight: bold; font-size: 125%">{% include {{ last_bench.reports.blog_speed_headline_html }} %}</span>

<div style="text-align: center;">
    <a href="{{ last_bench.url | relative_url }}">(Link to the latest full-details comparison report)</a>
</div>

<h2 style="text-align: center;">YJIT Results Over Time</h2>

{% include reports/blog_timeline.html %}

<h2 style="text-align: center;">Latest Results vs CRuby and MJIT</h2>

<div style="text-align: center;">
  <a href="{{ last_bench.url | relative_url }}">Click through for a full text report</a>
</div>

<div>
<a href="{{ last_bench.url | relative_url }}">
{% include {{last_bench.reports.blog_speed_details_svg}} %}
</a>
</div>

Or would you like the full firehose of [older benchmark results?](history)
