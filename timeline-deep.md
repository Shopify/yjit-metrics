---
layout: basic
---

<h2 style="text-align: center;">YJIT Results Over Time</h2>

<div class="timeline_report">
{% include reports/blog_timeline.html %}
</div>

<script>
    document.getElementById("bottom_selection_checkboxes").style.display = "block";
    var checkboxes = document.querySelectorAll("#bottom_selection_checkboxes li input");

    function setHashParamFromCheckboxes() {
        //console.log("setHashParamFromCheckboxes");
        var newHash = "";
        checkboxes.forEach(function (cb) {
            if(cb.checked) {
                var bench = cb.getAttribute("data-benchmark");
                newHash += "+" + bench
            }
        });
        newHash = newHash.slice(1); // Remove extra leading plus

        window.location.hash = newHash;
    }

    function setCheckboxesFromHashParam() {
        var hash = window.location.hash;
        var benchmarks = hash.slice(1).split("+");

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
            if(series.visible && series.value_range[0] < minY) {
                minY = series.value_range[0];
            }
            if(series.visible && series.value_range[1] > maxY) {
                maxY = series.value_range[1];
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
                    .x(function(d) { return xAxisFunc(d.date); })
                    .y(function(d) { return yAxisFunc(d.value); })
                    );

                // Rescale the circles
                var svgCircles = svgGroup.selectAll("circle.whiskerdot." + seriesName)
                    .data(series.data)
                    .attr("cy", function(d) { return yAxisFunc(d.value); })
                    ;

                var whiskerStrokeWidth = 1.0;
                var whiskerBarWidth = 5;

                var middleLines = svgGroup.selectAll("line.whiskercenter." + seriesName)
                    .data(series.data)
                    .attr("y1", function(d) { return yAxisFunc(d.value - 2 * d.stddev); })
                    .attr("y2", function(d) { return yAxisFunc(d.value + 2 * d.stddev); })
                    ;

                var topWhiskers = svgGroup.selectAll("line.whiskertop." + seriesName)
                    .data(series.data)
                    .attr("y1", function(d) { return yAxisFunc(d.value + 2 * d.stddev); })
                    .attr("y2", function(d) { return yAxisFunc(d.value + 2 * d.stddev); })
                    ;

                var bottomWhiskers = svgGroup.selectAll("line.whiskerbottom." + seriesName)
                    .data(series.data)
                    .attr("y1", function(d) { return yAxisFunc(d.value - 2 * d.stddev); })
                    .attr("y2", function(d) { return yAxisFunc(d.value - 2 * d.stddev); })
                    ;
            }
        });

    }

    window.addEventListener("hashchange", function () {
        setCheckboxesFromHashParam();
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