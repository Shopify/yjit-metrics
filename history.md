---
layout: basic
---

Here's a full historical listing of raw results of YJIT benchmark runs, including comparison
with other Rubies.

{% assign dates = site.benchmarks | map: "date_str" | uniq %}
{% for day in dates reversed %} <h3>{{ day }}</h3>
  {% assign date_benchmarks = site.benchmarks | where: "date_str", day | sort: "timestamp" %}
  {% for benchmark in date_benchmarks reversed %}

  <h4 id="{{benchmark.timestamp}}">{{benchmark.timestamp}}</h4> <a href="#{{benchmark.timestamp}}">(permalink)</a>

  <a href="{{ benchmark.reports.share_speed }}"> <img src="{{ benchmark.reports.share_speed_svg }}" />
  Click through for text report</a><br/>

  Raw JSON data:<br/>
  <ul> {% for result in benchmark.test_results %} <li><a href="{{result[1]}}">{{result[0]}}</a></li> {% endfor %} </ul>

  {% endfor %}

{% endfor %}
