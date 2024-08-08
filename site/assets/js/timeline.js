var timeParser = d3.timeParse("%Y %m %d %H %M %S");
var timePrinter = d3.timeFormat("%b %d %I%p");
var data_series;
var all_series_time_range;

document.timeline_data = {} // For sharing data w/ handlers

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

function buildUpdateAllFromCheckbox(seriesMatches) {
  return function updateAllFromCheckbox(cb) {
    var bench = cb.getAttribute("data-benchmark");
    var legendBox = document.querySelector("#timeline_legend_child li[data-benchmark=\"" + bench + "\"]");
    var graphSeries = document.querySelector("svg g.prod_ruby_with_yjit-" + bench);

    var thisDataSeries;
    if(data_series) {
      data_series.forEach(function (series) {
        if(seriesMatches(series, bench)) {
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

// Code borrowed from https://d3-graph-gallery.com/graph/line_brushZoom.html
var idleTimeout = null;

function idled() { idleTimeout = null; }

var drawWhiskers = false;
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

function setupTimeline(opts) {
  drawWhiskers = opts.whiskers;

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
