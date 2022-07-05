---
layout: basic
---

<h2 style="text-align: center;">YJIT Stats Over Time</h2>

<div class="timeline_report">
{% include reports/yjit_stats_timeline.html %}
</div>

<script>
    document.getElementById("bottom_selection_checkboxes").style.display = "block";
    var checkboxes = document.querySelectorAll("#bottom_selection_checkboxes li input");
    var stats_select = document.getElementById("stat_field_dropdown_select");

    function setHashParamFromCheckboxes() {
        //console.log("setHashParamFromCheckboxes");
        var newHash = document.timeline_data.current_stat;
        checkboxes.forEach(function (cb) {
            if(cb.checked) {
                var bench = cb.getAttribute("data-benchmark");
                newHash += "+" + bench
            }
        });

        window.location.hash = newHash;
    }

    function setCheckboxesFromHashParam() {
        var hash = window.location.hash;
        var benchmarks = hash.slice(1).split("+");
        document.timeline_data.current_stat = benchmarks.shift();
        stats_select.value = document.timeline_data.current_stat;

        var benchHash = {};
        benchmarks.forEach(function (bench) {
            benchHash[bench] = true;
        });

        checkboxes.forEach(function (cb) {
            var bench = cb.getAttribute("data-benchmark");
            if(benchHash[bench]) {
                if(!cb.checked) {
                    cb.checked = true;
                    updateCheckbox(cb);
                }
            } else {
                if(cb.checked) {
                    cb.checked = false;
                    updateCheckbox(cb);
                }
            }
        });
    }

    function updateCheckbox(cb) {
        var bench = cb.getAttribute("data-benchmark");
        var legendBox = document.querySelector("#timeline_legend_child li[data-benchmark=\"" + bench + "\"]");
        var graphSeries = document.querySelector("svg g.prod_ruby_with_yjit-" + bench);

        var thisDataSeries;
        data_series.forEach(function (series) {
            if(series.name == "prod_ruby_with_yjit-" + bench) {
                thisDataSeries = series;
            }
        });

        if(cb.checked) {
            /* Make series visible */
            thisDataSeries.visible = true;
            legendBox.style.display = "inline-block";
            graphSeries.style.visibility = "visible";
        } else {
            /* Make series invisible */
            thisDataSeries.visible = false;
            legendBox.style.display = "none";
            graphSeries.style.visibility = "hidden";
        }

    }

    function rescaleGraphFromCheckboxes() {
        // Find the new data scale based on visible series
        var minY = 0.0;
        var maxY = 1.0;
        data_series.forEach(function (series) {
            let valueRange = series.value_range[document.timeline_data.current_stat];
            console.log("Finding value range for rescale", document.timeline_data.current_stat, valueRange);
            if(series.visible && valueRange[0] < minY) {
                minY = valueRange[0];
            }
            if(series.visible && valueRange[1] > maxY) {
                maxY = valueRange[1];
            }
        });
        var yAxis = document.timeline_data.y_axis;
        var yAxisFunc = document.timeline_data.y_axis_function;
        var xAxisFunc = document.timeline_data.x_axis_function;

        yAxisFunc.domain([minY, maxY]);
        yAxis.scale(yAxisFunc);
        document.timeline_data.top_svg_group.call(yAxis);

        // Rescale the visible graph lines
        data_series.forEach(function (series) {
            if(series.visible) {
                var seriesName = "prod_ruby_with_yjit-" + series.benchmark;
                var svgGroup = d3.select("svg g." + seriesName);

                // Rescale the graph line
                var svgPath = svgGroup.select("path");
                svgPath.datum(series.data).attr("d", d3.line()
                    .x(function(d) { return xAxisFunc(d.time); })
                    .y(function(d) { return yAxisFunc(d[document.timeline_data.current_stat]); })
                    );

                // Rescale the circles
                var svgCircles = svgGroup.selectAll("circle.centerdot." + seriesName)
                    .data(series.data)
                    .attr("cy", function(d) { return yAxisFunc(d[document.timeline_data.current_stat]); })
                    ;
            }
        });

    }

    window.addEventListener("hashchange", function () {
        setCheckboxesFromHashParam();
    });
    stats_select.addEventListener("change", function () {
        // Set up new timeline_data.current_stat
        document.timeline_data.current_stat = stats_select.value;
        console.log("Setting current stat to", document.timeline_data.current_stat);

        setHashParamFromCheckboxes(); // new current_stat goes into the hashparam
        rescaleGraphFromCheckboxes(); // it also resets the graph scaling
    });

    setCheckboxesFromHashParam();
    rescaleGraphFromCheckboxes();

    checkboxes.forEach(function (cb) {
        cb.addEventListener('change', function (event) {
            updateCheckbox(this);
            rescaleGraphFromCheckboxes();
            setHashParamFromCheckboxes();
        });
    });
</script>
