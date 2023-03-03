---
layout: basic
---

<!-- Load d3.js -->
<script src="https://d3js.org/d3.v5.js"></script>

<h2 style="text-align: center;">YJIT Memory Usage Over Time</h2>

<script>
var timeParser = d3.timeParse("%Y %m %d %H %M %S");
var timePrinter = d3.timeFormat("%b %d %I%p");
var commaPrinter = d3.format(",d");
var data_series;
var all_series_time_range;

document.timeline_data = {} // For sharing data w/ handlers
</script>

<p>
  To zoom in, drag over the time range you want to see. Double-click to zoom back out.
</p>

<div class="timeline_report">
    <img class="graph-loading" src="/images/loading.gif" height="32" width="32" style="display: none" />
    <div class="graph-error" style="display: none"><span style="color: red; font-size: 300%;">Error Loading Data (please reload page)</span></div>
    <form>
        <fieldset id="plat-select-fieldset" style="border: 1px solid black">
            <legend>Select Dataset</legend>

            <input type="radio" id="platform-radio-yjit-x86-recent" name="plat-data-select" value="x86_64.recent" />
            <label for="platform-radio-x86-recent">x86_64 Recent</label>

            <input type="radio" id="platform-radio-yjit-x86-recent" name="plat-data-select" value="x86_64.all_time" checked />
            <label for="platform-radio-x86-recent">x86_64 All-Time</label>

            <input type="radio" id="platform-radio-yjit-aarch-recent" name="plat-data-select" value="aarch64.recent" />
            <label for="platform-radio-aarch-recent">ARM64 Recent</label>

            <input type="radio" id="platform-radio-yjit-aarch-recent" name="plat-data-select" value="aarch64.all_time" />
            <label for="platform-radio-aarch-recent">ARM64 All-Time</label>
        </fieldset>
    </form>
    {% include reports/memory_timeline.html %}
</div>

<script>
// D3 line graph, based on https://www.d3-graph-gallery.com/graph/line_basic.html
// set the dimensions and margins of the graph
var margin = {top: 10, right: 30, bottom: 70, left: 60},
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
    .domain([new Date(), new Date()])
    .range([ 0, width ]);
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
        .domain([0, 1.0])  // Dynamically set from data later
        .range([ height, 0 ]);
document.timeline_data.y_axis_function = y; /* Export for the event handlers */
document.timeline_data.y_axis = d3.axisLeft(y).tickFormat(d => `${(d / (1024 * 1024)).toFixed(1)} MiB`);
document.timeline_data.top_svg_group = svg.append("g")
  .call(document.timeline_data.y_axis);

var whiskerStrokeWidth = 1.0;
var whiskerBarWidth = 5;

var clip = svg.append("defs").append("svg:clipPath")
    .attr("id", "clip")
    .append("svg:rect")
    .attr("width", width + 30 )
    .attr("height", height + 20 )
    .attr("x", 0)
    .attr("y", -20);

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
    xAxisGroup.transition().duration(1000).call(xAxis)
    svg
        .selectAll("circle.whiskerdot")
        .transition().duration(1000)
        .attr("cx", function(d) { return x(d.date) } )
        .attr("cy", function(d) { return y(d.value) } )
        ;

    svg
        .selectAll("path.line")
        .transition().duration(1000)
        .attr("d", d3.line()
            .x(function(d) { return x(d.date) })
            .y(function(d) { return y(d.value) })
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
        let valueRange = series.value_range;
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
        group.selectAll("path")
        .data([item.data])
        .join("path")
        .attr("class", "line")
        .attr("fill", "none")
        .attr("stroke", item.color)
        .attr("stroke-width", 1.5)
        .attr("d", d3.line()
            .x(function(d) { return x(d.date) })
            .y(function(d) { return y(d.value) })
            )
        .attr("clip-path", "url(#clip)");

        // Add a circle at each datapoint
        var circles = group.selectAll("circle.whiskerdot." + item.name)
        .data(item.data, (d) => d.date)
        .join("circle")
        .attr("class", "whiskerdot " + item.name)
        .attr("fill", item.color)
        .attr("r", 4.0)
        .attr("cx", function(d) { return x(d.date) } )
        .attr("cy", function(d) { return y(d.value) } )
        .attr("data-tooltip", function(d) { return item.benchmark + " at " + timePrinter(d.date) + ": " + commaPrinter(d.value) + " bytes<br/>" + item.platform + " Ruby " + d.ruby_desc; } )
        .attr("clip-path", "url(#clip)")
        ;
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

// Default to x86_64 YJIT recent-only data
setRequestPending();
fetch("/reports/timeline/memory_timeline.data.x86_64.all_time.js").then(function (response) {
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
                fetch("/reports/timeline/memory_timeline.data." + newDataSet + ".js").then(function(response) {
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

// Handle legend and checkboxes
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
            }
        } else {
            if(cb.checked) {
                cb.checked = false;
            }
        }
    });
}

function updateAllFromCheckboxes() {
    checkboxes.forEach(function(cb) {
        updateAllFromCheckbox(cb);
    });
}

function updateAllFromCheckbox(cb) {
    var bench = cb.getAttribute("data-benchmark");
    var legendBox = document.querySelectorAll("#timeline_legend_child li[data-benchmark=\"" + bench + "\"]");

    // Find the graph series for this benchmark
    var yjitGraphSeries = document.querySelector("svg g.prod_ruby_with_yjit-" + bench);
    var nojitGraphSeries = document.querySelector("svg g.prod_ruby_no_jit-" + bench);

    var thisYJITDataSeries;
    var thisNoJITDataSeries;
    if(data_series) {
        data_series.forEach(function (series) {
            if(series.name == "prod_ruby_with_yjit-" + bench) {
                thisYJITDataSeries = series;
            }
            if(series.name == "prod_ruby_no_jit-" + bench) {
                thisNoJITDataSeries = series;
            }
        });
    }

    if(cb.checked) {
        /* Make series visible */
        if(thisYJITDataSeries) { thisYJITDataSeries.visible = true; }
        if(thisNoJITDataSeries) { thisNoJITDataSeries.visible = true; }
        legendBox.forEach(function(elt) { elt.style.display = "inline-block"; });
        if(yjitGraphSeries) { yjitGraphSeries.style.visibility = "visible"; }
        if(nojitGraphSeries) { nojitGraphSeries.style.visibility = "visible"; }
    } else {
        /* Make series invisible */
        if(thisYJITDataSeries) { thisYJITDataSeries.visible = false; }
        if(thisNoJITDataSeries) { thisNoJITDataSeries.visible = false; }
        legendBox.forEach(function(elt) { elt.style.display = "none"; });
        if(yjitGraphSeries) { yjitGraphSeries.style.visibility = "hidden"; }
        if(nojitGraphSeries) { nojitGraphSeries.style.visibility = "hidden"; }
    }
}

window.addEventListener("hashchange", function () {
    setCheckboxesFromHashParam();
    updateAllFromCheckboxes();
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