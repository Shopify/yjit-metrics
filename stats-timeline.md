---
layout: basic
---
<script src="https://d3js.org/d3.v5.js"></script>

<h2 style="text-align: center;">YJIT Stats Over Time</h2>

<p>
  "Overall" is a mean of all listed benchmarks.
</p>

<p>
  To zoom in, drag over the time range you want to see. Double-click to zoom back out.
</p>

<script>
var timeParser = d3.timeParse("%Y %m %d %H %M %S");
var timePrinter = d3.timeFormat("%b %d %I%p");
var data_series;
var all_series_time_range;

document.timeline_data = {} // For sharing data w/ handlers
</script>

<div class="timeline_report">
    <img class="graph-loading" src="/images/loading.gif" height="32" width="32" style="display: none" />
    <div class="graph-error" style="display: none"><span style="color: red; font-size: 300%;">Error Loading Data (please reload page)</span></div>
    <form>
        <fieldset id="plat-select-fieldset" style="border: 1px solid black">
            <legend>Select Dataset</legend>

            <input type="radio" id="platform-radio-x86-recent" name="plat-data-select" value="x86_64.recent" checked />
            <label for="platform-radio-x86-recent">Xeon x86_64 Recent</label>

            <input type="radio" id="platform-radio-x86-recent" name="plat-data-select" value="x86_64.all_time" />
            <label for="platform-radio-x86-recent">Xeon x86_64 All-Time</label>

            <input type="radio" id="platform-radio-aarch-recent" name="plat-data-select" value="aarch64.recent" />
            <label for="platform-radio-aarch-recent">AWS Graviton ARM64 Recent</label>

            <input type="radio" id="platform-radio-aarch-recent" name="plat-data-select" value="aarch64.all_time" />
            <label for="platform-radio-aarch-recent">AWS Graviton ARM64 All-Time</label>
        </fieldset>
    </form>
{% include reports/yjit_stats_timeline.html %}
</div>

<script>
    // D3 line graph is based on https://www.d3-graph-gallery.com/graph/line_basic.html

    // set the dimensions and margins of the graph
    var margin = {top: 10, right: 30, bottom: 70, left: 40},
        width = 800 - margin.left - margin.right,
        height = 400 - margin.top - margin.bottom;

    // append the svg object to the body of the page
    var svg = d3.select("#timeline_rs_chart")
    .append("svg")
        .attr("viewBox", "0 0 " + (width + margin.left + margin.right) + " " + (height + margin.top + margin.bottom))
        .attr("xmlns", "http://www.w3.org/2000/svg")
        .attr("xmlns:xlink", "http://www.w3.org/1999/xlink")
        //.attr("width", width + margin.left + margin.right)
        //.attr("height", height + margin.top + margin.bottom)
    .append("g")
        .attr("transform",
            "translate(" + margin.left + "," + margin.top + ")");

    // Add X axis --> it is a date format
    var x = d3.scaleTime()
        .domain([0, 1])
        .range([ 0, width ]);
    //.domain(d3.extent(all_series_time_range))
    document.timeline_data.x_axis_function = x; /* Export for the event handlers */
    var xAxis = d3.axisBottom(x);
    var xAxisGroup = svg.append("g")
        .attr("transform", "translate(0," + height + ")")
        .attr("class", "x_axis_group")
        .call(xAxis);
    xAxisGroup.selectAll("text")
        .attr("transform", "rotate(-60)")
        .style("text-anchor", "end");
    document.timeline_data.x_axis = xAxis;
    document.timeline_data.x_axis_group = xAxisGroup;

    // Add Y axis
    var y = d3.scaleLinear()
        .domain([0, 1.0])  // Dynamically generate later
        .range([ height, 0 ]);
    document.timeline_data.y_axis_function = y; /* Export for the event handlers */
    document.timeline_data.y_axis = d3.axisLeft(y);
    let formatValue = d3.format(".2s");
    document.timeline_data.y_axis.tickFormat(function (d) { return formatValue(d); });
    document.timeline_data.top_svg_group = svg.append("g")
        .call(document.timeline_data.y_axis);

    var clip = svg.append("defs").append("svg:clipPath")
        .attr("id", "clip")
        .append("svg:rect")
        .attr("width", width + 30 )
        .attr("height", height )
        .attr("x", 0)
        .attr("y", 0);

    // Code borrowed from https://d3-graph-gallery.com/graph/line_brushZoom.html
    var idleTimeout = null;

    function idled() { idleTimeout = null; }

    function updateChart() {

        const extent = d3.event.selection

        // If no selection, back to initial coordinate. Otherwise, update X axis domain
        if (!extent) {
            if (!idleTimeout) {
                return (idleTimeout = setTimeout(idled, 350)); // This allows to wait a little bit
            }
            x.domain(d3.extent(all_series_time_range));
        } else {
            x.domain([x.invert(extent[0]), x.invert(extent[1])]);
            // Remove the grey brush area as soon as the selection has been done
            document.timeline_data.top_svg_group.select(".brush").call(brush.move, null);
        }
        // Update axis and circle position
        // Note: this doesn't seem to work with the other update function. Why not?
        xAxisGroup.transition().duration(1000).call(xAxis)
        svg
            .selectAll(".centerdot.circle")
            .transition().duration(1000)
            .attr("cx", function(d) { return x(d.time) } )
            .attr("cy", function(d) { return y(d[document.timeline_data.current_stat]) } )

        svg
            .selectAll(".line")
            .transition().duration(1000)
            .attr("d", d3.line()
                .x(function(d) { return x(d.time) })
                .y(function(d) { return y(d[document.timeline_data.current_stat]) })
            );
    }

    var brush = d3.brushX()                 // Add the brush feature using the d3.brush function
        .extent( [ [0,0], [width,height] ] ) // initialise the brush area: start at 0,0 and finishes at width,height: it means I select the whole graph area
        .on("end", updateChart);

    document.timeline_data.top_svg_group
        .append("g")
        .attr("class", "brush")
        .call(brush);

    function updateDomainsAndAxesFromData() {
        // Find the new data scale based on visible series
        var minY = 0.0;
        var maxY = 1.0;
        var minX = data_series[0].time_range[0];
        var maxX = data_series[0].time_range[1];
        data_series.forEach(function (series) {
            let valueRange = series.value_range[document.timeline_data.current_stat];
            if(series.visible && valueRange[0] < minY) {
                minY = valueRange[0];
            }
            if(series.visible && valueRange[1] > maxY) {
                maxY = valueRange[1];
            }
            if(series.visible && series.time_range[0] < minX) {
                minX = series.time_range[0];
            }
            if(series.visible && series.time_range[1] > maxX) {
                maxX = series.time_range[1];
            }
        });
        var yAxis = document.timeline_data.y_axis;
        var yAxisFunc = document.timeline_data.y_axis_function;

        var xAxis = document.timeline_data.x_axis;
        var xAxisFunc = document.timeline_data.x_axis_function;

        yAxisFunc.domain([minY, maxY]);
        yAxis.scale(yAxisFunc);
        document.timeline_data.top_svg_group.call(yAxis);

        xAxisFunc.domain([minX, maxX]);
        xAxis.scale(xAxisFunc);
        document.timeline_data.x_axis_group.call(xAxis);

        all_series_time_range = [minX, maxX];
    }

    // Using JS values like data_series, update the SVG graph data
    function updateGraphFromData() {
        updateDomainsAndAxesFromData();

        // Add top-level SVG groups for data series
        svg.selectAll("g.svg_tl_data")
            .data(data_series, (item) => item.name)
            .join("g")
                .attr("class", d => "svg_tl_data " + d.name)
                .attr("visibility", d => d.visible ? "visible" : "hidden")
                ;

        data_series.forEach(function(item) {
            var group = svg.select("svg g.svg_tl_data." + item.name);

            // Add the graph line
            var lines = group.selectAll("path")
                .data([item.data])
                .join("path")
                .attr("class", "line")
                .attr("fill", "none")
                .attr("stroke", item.color)
                .attr("stroke-width", 1.5)
                .attr("d", d3.line()
                .x(function(d) { return x(d.time) })
                .y(function(d) { return y(d[document.timeline_data.current_stat]) })
                ).attr("clip-path", "url(#clip)");

            // Add a circle at each datapoint
            var circles = group.selectAll("circle.centerdot." + item.name)
                .data(item.data, (d) => d.time).join("circle")
                .attr("class", "circle centerdot " + item.name)
                .attr("fill", item.color)
                .attr("r", 1.5)
                .attr("cx", function(d) { return x(d.time) } )
                .attr("cy", function(d) { return y(d[document.timeline_data.current_stat]) } )
                .attr("data-tooltip", function(d) {
                    return item.benchmark + " at " + timePrinter(d.time) + ": " +
                        (d[document.timeline_data.current_stat]).toFixed(1) +
                        "<br/>" + item.platform + " Ruby " + d.ruby_desc;
                })
                .attr("clip-path", "url(#clip)");
        });
    }

    function rescaleGraphFromFetchedData() {
        updateAllFromCheckboxes();
        updateGraphFromData();
    }

    function setRequestPending() {
        var loader = document.querySelector(".graph-loading");
        loader.style.display = "block";
        var error = document.querySelector(".graph-error");
        error.style.display = "none";
    }

    function setRequestFinished() {
        var loader = document.querySelector(".graph-loading");
        loader.style.display = "none";
        var error = document.querySelector(".graph-error");
        error.style.display = "none";
    }

    function setRequestError() {
        var loader = document.querySelector(".graph-loading");
        loader.style.display = "none";
        var error = document.querySelector(".graph-error");
        error.style.display = "block";
    }

    // Default to x86_64 recent-only data
    setRequestPending();
    fetch("/reports/timeline/yjit_stats_timeline.data.x86_64.recent.js").then(function (response) {
        if(response.ok) {
            return response.text().then(function (data) {
                setRequestFinished();
                eval(data);
                updateGraphFromData();
                rescaleGraphFromFetchedData();

                var handler = function(event) {
                    // Did they click a platform radio button? If not, we ignore it.
                    if(!event.target.matches('#plat-select-fieldset input[type="radio"]')) return;

                    setRequestPending();
                    var newDataSet = event.target.value;
                    fetch("/reports/timeline/yjit_stats_timeline.data." + newDataSet + ".js").then(function(response) {
                        if(response.ok) {
                            return response.text().then(function(data) {
                                setRequestFinished();
                                eval(data);
                                rescaleGraphFromFetchedData();
                            });
                        } else {
                            setRequestError();
                        }
                    });
                };
                // If anybody clicks a platform radio button, send a new request and cancel the old one, if any.
                document.addEventListener('click', handler);
            });
        } else {
            setRequestError();
        }
    });

    // Handle legend, checkboxes and stats dropdown
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
                }
            } else {
                if(cb.checked) {
                    cb.checked = false;
                }
            }
        });
    }

    function updateAllFromCheckboxes() {
        checkboxes.forEach(function (cb) {
            updateAllFromCheckbox(cb);
        });
    }

    function updateAllFromCheckbox(cb) {
        var bench = cb.getAttribute("data-benchmark");
        var legendBox = document.querySelector("#timeline_legend_child li[data-benchmark=\"" + bench + "\"]");
        var graphSeries = document.querySelector("svg g.prod_ruby_with_yjit-" + bench);

        var thisDataSeries;
        if(data_series) {
            data_series.forEach(function (series) {
                if(series.config == (series.platform + "_prod_ruby_with_yjit") && series.benchmark == bench) {
                    thisDataSeries = series;
                }
            });
        }

        if(cb.checked) {
            /* Make series visible */
            if(thisDataSeries) { thisDataSeries.visible = true; }
            legendBox.style.display = "inline-block";
            if(graphSeries) { graphSeries.style.visibility = "visible"; }
        } else {
            /* Make series invisible */
            if(thisDataSeries) { thisDataSeries.visible = false; }
            legendBox.style.display = "none";
            if(graphSeries) { graphSeries.style.visibility = "hidden"; }
        }

    }

    window.addEventListener("hashchange", function () {
        setCheckboxesFromHashParam();
        updateAllFromCheckboxes();
    });
    stats_select.addEventListener("change", function () {
        // Set up new timeline_data.current_stat
        document.timeline_data.current_stat = stats_select.value;
        console.log("Setting current stat to", document.timeline_data.current_stat);

        setHashParamFromCheckboxes(); // new current_stat goes into the hashparam
        updateGraphFromData();
    });

    setCheckboxesFromHashParam();
    updateAllFromCheckboxes();

    checkboxes.forEach(function (cb) {
        cb.addEventListener('change', function (event) {
            updateAllFromCheckbox(this);
            updateGraphFromData();
            setHashParamFromCheckboxes();
        });
    });
</script>
