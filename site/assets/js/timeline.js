var timeParser = d3.timeParse("%Y %m %d %H %M %S");
var timePrinter = d3.timeFormat("%b %d %I%p");
var data_series;
var all_series_time_range;
var svg;
var checkboxes;

var whiskerStrokeWidth = 1.0;
var whiskerBarWidth = 5;

document.timeline_data = {} // For sharing data w/ handlers

function initSVG(opts) {
  // D3 line graph, based on https://www.d3-graph-gallery.com/graph/line_basic.html
  // set the dimensions and margins of the graph
  var margin = {top: 10, right: 30, bottom: 70, left: opts.marginLeft || 40},
      width = 800 - margin.left - margin.right,
      height = 400 - margin.top - margin.bottom;

  // append the svg object to the body of the page
  svg = d3.select("#timeline_rs_chart")
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
          .domain([0, 1.0])  // Dynamically generate later
          .range([ height, 0 ]);
  document.timeline_data.y_axis_function = y; /* Export for the event handlers */
  document.timeline_data.y_axis = d3.axisLeft(y);

  document.timeline_data.y_axis.tickFormat( opts.tickFormat || d3.format(".2s") );
  document.timeline_data.top_svg_group = svg.append("g")
    .call(document.timeline_data.y_axis);

  // Define viewport to clip graphs to.
  svg.append("defs").append("svg:clipPath")
      .attr("id", "clip")
      .append("svg:rect")
      .attr("width", width)
      .attr("height", height)
      .attr("x", 0)
      .attr("y", 0);

  var brush = d3.brushX()                 // Add the brush feature using the d3.brush function
      .extent( [ [0,0], [width,height] ] ) // initialise the brush area: start at 0,0 and finishes at width,height: it means I select the whole graph area
      .on("end", updateChart);
  document.timeline_data.brush = brush;

  document.timeline_data.top_svg_group
      .append("g")
      .attr("class", "brush")
      .call(brush);
}

function rescaleGraphFromFetchedData() {
  updateAllFromCheckboxes();
  updateGraphFromData();
}

function setRequestPending() {
  document.querySelector(".graph-loading").style.display = "block";
  document.querySelector(".graph-error").style.display = "none";
}

function setRequestFinished() {
  document.querySelector(".graph-loading").style.display = "none";
  document.querySelector(".graph-error").style.display = "none";
}

function setRequestError(x) {
  console.error(x);
  document.querySelector(".graph-loading").style.display = "none";
  document.querySelector(".graph-error").style.display = "block";
}

function updateAllFromCheckboxes() {
  checkboxes.forEach(function (cb) {
    updateAllFromCheckbox(cb);
  });
}

function buildUpdateDomainsAndAxesFromData(getSeriesValueRange){
  return function updateDomainsAndAxesFromData() {
    // Find the new data scale based on visible series
    var minY = 0.0;
    var maxY = 1.0;
    var minX = data_series[0].time_range[0];
    var maxX = data_series[0].time_range[1];
    data_series.forEach(function (series) {
      let valueRange = getSeriesValueRange(series);
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
}

function updateAllFromCheckbox(cb) {
    var bench = cb.getAttribute("data-benchmark");
    var legendBox = document.querySelectorAll("#timeline_legend_child li[data-benchmark=\"" + bench + "\"]");

    // Find the graph series for this benchmark
    var matchingGraphs = document.querySelectorAll("svg g.benchmark-" + bench);
    var matchingSeries = [];
    if(data_series) {
      data_series.forEach(function (series) {
        if(series.benchmark == bench) {
          matchingSeries.push(series);
        }
      });
    }

    var visibility = cb.checked ? "visible" : "hidden";
    var display = cb.checked ? "inline-block" : "none";

    matchingSeries.forEach(function(series) {
      series.visible = cb.checked;
    });
    legendBox.forEach(function(elt) {
      elt.style.display = display;
    });
    matchingGraphs.forEach(function(series) {
      series.style.visibility = visibility;
    });
}

function setCheckboxesFromHashParam(cb) {
  var hash = window.location.hash;
  var benchmarks = hash.slice(1).split("+");
  if(cb) cb(benchmarks);

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

function setHashParamFromCheckboxes() {
  var newHash = document.timeline_data.current_stat || "";

  checkboxes.forEach(function (cb) {
    if(cb.checked) {
      var bench = cb.getAttribute("data-benchmark");
      newHash += "+" + bench
    }
  });

  if (newHash[0] == "+"){
    newHash = newHash.slice(1); // Remove extra leading plus
  }

  window.location.hash = newHash;
}

// Code borrowed from https://d3-graph-gallery.com/graph/line_brushZoom.html
var idleTimeout = null;

function idled() { idleTimeout = null; }

var drawWhiskers = false;
function updateChart() {
    const extent = d3.event.selection
    var x = document.timeline_data.x_axis_function;
    var y = document.timeline_data.y_axis_function;
    var xAxis = document.timeline_data.x_axis;
    var xAxisGroup = document.timeline_data.x_axis_group;

    // If no selection, back to initial coordinate. Otherwise, update X axis domain
    if (!extent) {
        if (!idleTimeout) {
            return (idleTimeout = setTimeout(idled, 350)); // This allows to wait a little bit
        }
        x.domain(d3.extent(all_series_time_range));
    } else {
        x.domain([x.invert(extent[0]), x.invert(extent[1])]);
        // Remove the grey brush area as soon as the selection has been done
        document.timeline_data.top_svg_group.select(".brush").call(document.timeline_data.brush.move, null);
    }
    // Update axis and circle position
    // Note: this doesn't seem to work with the other update function. Why not?
    xAxisGroup.transition().duration(1000).call(xAxis)

    updateChartCallback({svg, x, y});
}

function updateChartCallback({svg, x, y}) {
    svg
        .selectAll("circle.whiskerdot")
        .transition().duration(1000)
        .attr("cx", function(d) { return x(d.date) } )
        .attr("cy", function(d) { return y(d.value) } )
        ;

    if (drawWhiskers) {
      svg
        .selectAll("line.whiskercenter")
        .transition().duration(1000)
        .attr("x1", function(d) { return x(d.date) } )
        .attr("y1", function(d) { return y(d.value - 2 * d.stddev) } )
        .attr("x2", function(d) { return x(d.date) } )
        .attr("y2", function(d) { return y(d.value + 2 * d.stddev) } )
        ;

      svg
        .selectAll("line.whiskertop")
        .transition().duration(1000)
        .attr("x1", function(d) { return x(d.date) - whiskerBarWidth / 2.0 } )
        .attr("y1", function(d) { return y(d.value + 2 * d.stddev) } )
        .attr("x2", function(d) { return x(d.date) + whiskerBarWidth / 2.0 } )
        .attr("y2", function(d) { return y(d.value + 2 * d.stddev) } )
        ;

      svg
        .selectAll("line.whiskerbottom")
        .transition().duration(1000)
        .attr("x1", function(d) { return x(d.date) - whiskerBarWidth / 2.0 } )
        .attr("y1", function(d) { return y(d.value - 2 * d.stddev) } )
        .attr("x2", function(d) { return x(d.date) + whiskerBarWidth / 2.0 } )
        .attr("y2", function(d) { return y(d.value - 2 * d.stddev) } )
        ;
    }

    svg
        .selectAll("path.line")
        .transition().duration(1000)
        .attr("d", d3.line()
            .x(function(d) { return x(d.date) })
            .y(function(d) { return y(d.value) })
        );
}

var updateDomainsAndAxesFromData = buildUpdateDomainsAndAxesFromData(function(series){
  return series.value_range;
});

function updateGraphFromData() {
    updateDomainsAndAxesFromData();
    var x = document.timeline_data.x_axis_function;
    var y = document.timeline_data.y_axis_function;

    // Add top-level SVG groups for data series
    svg.selectAll("g.svg_tl_data")
        .data(data_series, (item) => item.name)
        .join("g")
            .attr("class", d => "svg_tl_data " + d.name + " benchmark-" + d.benchmark)
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
        .attr("d",
          d3.line()
            .x(function(d) { return x(d.date) })
            .y(function(d) { return y(d.value) })
        ).attr("clip-path", "url(#clip)");

        // Add a circle at each datapoint
        group.selectAll("circle.whiskerdot." + item.name)
          .data(item.data, (d) => d.date)
          .join("circle")
          .attr("class", "whiskerdot " + item.name)
          .attr("fill", item.color)
          .attr("r", 4.0)
          .attr("cx", function(d) { return x(d.date) } )
          .attr("cy", function(d) { return y(d.value) } )
          .attr("data-tooltip", function(d) {
            return item.benchmark + " at " + timePrinter(d.date) + ": " +
              d.value.toFixed(1) + " sec" +
              "<br/>" + item.platform + " Ruby " + d.ruby_desc;
          })
          .attr("clip-path", "url(#clip)")
        ;

        // Add the whiskers, which are an I-shape of lines
        var middle_lines = group.selectAll("line.whiskercenter." + item.name)
        .data(item.data, (d) => d.date)
        .join("line")
        .attr("class", "whiskercenter " + item.name)
        .attr("stroke", "black")
        .attr("stroke-width", whiskerStrokeWidth)
        .attr("x1", function(d) { return x(d.date) } )
        .attr("y1", function(d) { return y(d.value - 2 * d.stddev) } )
        .attr("x2", function(d) { return x(d.date) } )
        .attr("y2", function(d) { return y(d.value + 2 * d.stddev) } )
        .attr("clip-path", "url(#clip)")
        ;

        var top_whiskers = group.selectAll("line.whiskertop." + item.name)
        .data(item.data, (d) => d.date)
        .join("line")
        .attr("class", "whiskertop " + item.name)
        .attr("stroke", "black")
        .attr("stroke-width", whiskerStrokeWidth)
        .attr("x1", function(d) { return x(d.date) - whiskerBarWidth / 2.0 } )
        .attr("y1", function(d) { return y(d.value + 2 * d.stddev) } )
        .attr("x2", function(d) { return x(d.date) + whiskerBarWidth / 2.0 } )
        .attr("y2", function(d) { return y(d.value + 2 * d.stddev) } )
        .attr("clip-path", "url(#clip)")
        ;

        var bottom_whiskers = group.selectAll("line.whiskerbottom." + item.name)
        .data(item.data, (d) => d.date)
        .join("line")
        .attr("class", "whiskerbottom " + item.name)
        .attr("stroke", "black")
        .attr("stroke-width", whiskerStrokeWidth)
        .attr("x1", function(d) { return x(d.date) - whiskerBarWidth / 2.0 } )
        .attr("y1", function(d) { return y(d.value - 2 * d.stddev) } )
        .attr("x2", function(d) { return x(d.date) + whiskerBarWidth / 2.0 } )
        .attr("y2", function(d) { return y(d.value - 2 * d.stddev) } )
        .attr("clip-path", "url(#clip)")
        ;
    });
}

function setupTimeline(opts) {
  initSVG(opts);

  drawWhiskers = opts.whiskers;

  // Handle legend and checkboxes
  document.getElementById("bottom_selection_checkboxes").style.display = "block";
  checkboxes = document.querySelectorAll("#bottom_selection_checkboxes li input");

  // Default to x86_64 recent-only data
  setRequestPending();
  fetch("/reports/timeline/"+opts.timelineType+"_timeline.data.x86_64.recent.js")
    .then(function (response) {
      if(!response.ok) {
        throw(new Error('Response failed: ' + response.statusText));
      }

      return response.text().then(function (data) {
        setRequestFinished();
        eval(data);
        updateGraphFromData();
        rescaleGraphFromFetchedData();
      });
    })
    .catch(setRequestError)
    .then(function(x) {
      var handler = function(event) {
        // Did they click a platform radio button? If not, we ignore it.
        if(!event.target.matches('#plat-select-fieldset input[type="radio"]')) return;

        setRequestPending();
        var newDataSet = event.target.value;
        fetch("/reports/timeline/"+opts.timelineType+"_timeline.data." + newDataSet + ".js").then(function(response) {
          if(!response.ok) {
            throw(new Error('Response failed: ' + response.statusText));
          }

          return response.text().then(function(data) {
            setRequestFinished();
            eval(data);
            rescaleGraphFromFetchedData();
          });
        }).catch(setRequestError);
      };

      // If anybody clicks a platform radio button, send a new request and cancel the old one, if any.
      document.addEventListener('click', handler);
    })
    .catch(console.error);

  window.addEventListener("hashchange", function () {
    setCheckboxesFromHashParam(opts.setCheckboxesFromHashParamCallback);
    updateAllFromCheckboxes();
  });

  setCheckboxesFromHashParam(opts.setCheckboxesFromHashParamCallback);
  updateAllFromCheckboxes();

  checkboxes.forEach(function (cb) {
    cb.addEventListener('change', function (event) {
      updateAllFromCheckbox(this);
      updateGraphFromData();
      setHashParamFromCheckboxes();
    });
  });
}
