---
layout: basic
---

Here's a full historical listing of raw results of YJIT benchmark runs, including comparison
with other Rubies.

{% assign dates = site.benchmarks | map: "date_str" | uniq | reverse %}
{% assign first_dates = dates | slice 0, 49 %}
{% assign later_dates = dates | slice 50, -1 %}

<!-- {% for day in dates %} {{day}} {% endfor %} -->
<!-- {% for day in first_dates %} {{day}} {% endfor %} -->
<!-- {% for day in later_dates %} {{day}} {% endfor %} -->

{% for day in first_dates %} <!-- <h3>{{ day }}</h3> -->
{% assign date_benchmarks = site.benchmarks | where: "date_str", day | sort: "timestamp" %}
{% for benchmark in date_benchmarks reversed %}

<h4 id="{{benchmark.timestamp}}">{{benchmark.date_str}} {{benchmark.time_str}}</h4>

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

{% for day in later_dates %}
{% for benchmark in date_benchmarks reversed %}
<h4 id="{{benchmark.timestamp}}">{{benchmark.date_str}} {{benchmark.time_str}}</h4>

<a href="{{ benchmark_url | relative_url }}"><button>Full Details for This Time</button></a>
{% endfor %}
{% endfor %}
