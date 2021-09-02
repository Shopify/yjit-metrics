---
layout: basic
---

{% assign last_bench = site.benchmarks | last %}

How is [YJIT's](https://github.com/Shopify/yjit) speed on its [benchmarks](https://github.com/Shopify/yjit-bench) as of <strong>{{last_bench.date_str}} {{last_bench.time_str}}</strong>?

<span style="font-weight: bold; font-size: 125%">{% include {{ last_bench.reports.blog_speed_headline_html }} %}</span>

<div style="width: 800px;">
<a href="{{ last_bench.url | relative_url }}">
{% include {{last_bench.reports.blog_speed_details_svg}} %}
Here are all the latest details as a full-text report.
</a>
</div>

Or would you like the full firehose of [older benchmark results?](history)
