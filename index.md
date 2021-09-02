---
layout: basic
---

How is [YJIT's](https://github.com/Shopify/yjit) speed on its [benchmarks](https://github.com/Shopify/yjit-bench)?

{% assign last_bench = site.benchmarks | last %}
{% include {{ last_bench.reports.blog_speed_headline_html }} %}

Here are [the latest details]({{last_bench.url}}).

{% assign dates = site.benchmarks | map: "date_str" | uniq %}
{% for day in dates reversed %} <h3>{{ day }}</h3>
  {% assign date_benchmarks = site.benchmarks | where: "date_str", day | sort: "timestamp" %}
  {% for benchmark in date_benchmarks reversed %}

  <div style="width: 500px;"> <img src="{{ benchmark.reports.blog_speed_details_svg }}" /></div> <br/>
  {{ benchmark.timestamp }} [Full data with tables]( {{ benchmark.reports.share_speed }} ) (raw JSON data: {% for result in benchmark.test_results %} [X]({{ result[1] }}) {% endfor %} )

  {% endfor %}

{% endfor %}
