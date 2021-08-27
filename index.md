# Latest YJIT Benchmarks

How is <a href="https://github.com/Shopify/yjit">YJIT</a> doing on its
<a href="https://github.com/Shopify/yjit-bench">benchmarks</a>?

{% assign dates = site.benchmarks | map: "date_str" | uniq %}
{% for day in dates %} <h3>{{ day }}</h3>
  {% assign date_benchmarks = site.benchmarks | where: "date_str", day | sort: "timestamp" %}
  {% for benchmark in date_benchmarks %}

  <div style="width: 500px;"> <img src="{{ benchmark.reports.share_speed_svg }}" /></div> <br/>
  {{ benchmark.timestamp }} [Full data with tables]( {{ benchmark.reports.share_speed }} ) (raw JSON data: {% for result in benchmark.test_results %} [X]({{ result[1] }}) {% endfor %} )

  {% endfor %}

{% endfor %}
