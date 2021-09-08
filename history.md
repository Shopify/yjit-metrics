---
layout: basic
---

Here's a full historical listing of raw results of YJIT benchmark runs, including comparison
with other Rubies.

{% assign dates = site.benchmarks | map: "date_str" | uniq %}
{% for day in dates reversed %} <!-- <h3>{{ day }}</h3> -->
  {% assign date_benchmarks = site.benchmarks | where: "date_str", day | sort: "timestamp" %}
  {% for benchmark in date_benchmarks reversed %}

  <h4 id="{{benchmark.timestamp}}">{{benchmark.date_str}} {{benchmark.time_str}}</h4> <!-- <a href="#{{benchmark.timestamp}}">(permalink)</a> -->

  <div style="width: 800px;">
  <a href="{{ benchmark.url | relative_url }}">
  {% include {{benchmark.reports.blog_speed_details_svg}} %}
  <button>Full Details for This Time</button>
  </a>
  </div>

  Raw JSON data:<br/>
  <ul> {% for result in benchmark.test_results %} <li><a href="{{result[1]}}">{{result[0]}}</a></li> {% endfor %} </ul>

  {% endfor %}

{% endfor %}
