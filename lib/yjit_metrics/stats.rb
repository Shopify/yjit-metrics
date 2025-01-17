# frozen_string_literal: true

# Statistical methods
module YJITMetrics
  module Stats
    def sum(values)
      return values.sum(0.0)
    end

    def sum_or_nil(values)
      return nil if values.nil?
        sum(values)
    end

    def mean(values)
      return values.sum(0.0) / values.size
    end

    def mean_or_nil(values)
      return nil if values.nil?
        mean(values)
    end

    def geomean(values)
      exponent = 1.0 / values.size
        values.inject(1.0, &:*) ** exponent
    end

    def geomean_or_nil(values)
      return nil if values.nil?
        geomean(values)
    end

    def stddev(values)
      return 0 if values.size <= 1

        xbar = mean(values)
        diff_sqrs = values.map { |v| (v-xbar)*(v-xbar) }
        # Bessel's correction requires dividing by length - 1, not just length:
        # https://en.wikipedia.org/wiki/Standard_deviation#Corrected_sample_standard_deviation
        variance = diff_sqrs.sum(0.0) / (values.length - 1)
        return Math.sqrt(variance)
    end

    def stddev_or_nil(values)
      return nil if values.nil?
        stddev(values)
    end

    def rel_stddev(values)
      stddev(values) / mean(values)
    end

    def rel_stddev_or_nil(values)
      return nil if values.nil?
        rel_stddev(values)
    end

    def rel_stddev_pct(values)
      100.0 * stddev(values) / mean(values)
    end

    def rel_stddev_pct_or_nil(values)
      return nil if values.nil?
        rel_stddev_pct(values)
    end

    # See https://en.wikipedia.org/wiki/Covariance#Definition and/or
    # https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Covariance (two-pass algorithm)
    def covariance(x, y)
      raise "Trying to take the covariance of two different-sized arrays!" if x.size != y.size

        x_mean = mean(x)
        y_mean = mean(y)

        cov = 0.0
        (0...(x.size)).each do |i|
          cov += (x[i] - x_mean) * (y[i] - y_mean) / x.size
        end

        cov
    end

    # See https://en.wikipedia.org/wiki/Pearson_correlation_coefficient
    # I'm not convinced this is correct. It definitely doesn't match the least-squares correlation coefficient below.
    def pearson_correlation(x, y)
      raise "Trying to take the Pearson correlation of two different-sized arrays!" if x.size != y.size

        ## Some random Ruby guy method
        #xx_prod = x.map { |xi| xi * xi }
        #yy_prod = y.map { |yi| yi * yi }
        #xy_prod = (0...(x.size)).map { |i| x[i] * y[i] }
        #
        #x_sum = x.sum
        #y_sum = y.sum
        #
        #num = xy_prod.sum - (x_sum * y_sum) / x.size
        #den = Math.sqrt(xx_prod.sum - x_sum ** 2.0 / x.size) * (yy_prod.sum - y_sum ** 2.0 / x.size)
        #
        #num/den

        # Wikipedia translation of the definition
        x_mean = mean(x)
        y_mean = mean(y)
        num = (0...(x.size)).map { |i| (x[i] - x_mean) * (y[i] - y_mean) }.sum
        den = Math.sqrt((0...(x.size)).map { |i| (x[i] - x_mean) ** 2.0 }.sum) *
            Math.sqrt((0...(x.size)).map { |i| (y[i] - y_mean) ** 2.0 }.sum)
        num / den
    end

    # See https://mathworld.wolfram.com/LeastSquaresFitting.html
    def least_squares_slope_intercept_and_correlation(x, y)
      raise "Trying to take the least-squares slope of two different-sized arrays!" if x.size != y.size

        x_mean = mean(x)
        y_mean = mean(y)

        xx_sum_of_squares = x.map { |xi| (xi - x_mean)**2.0 }.sum
        yy_sum_of_squares = y.map { |yi| (yi - y_mean)**2.0 }.sum
        xy_sum_of_squares = (0...(x.size)).map { |i| (x[i] - x_mean) * (y[i] - y_mean) }.sum

        slope = xy_sum_of_squares / xx_sum_of_squares
        intercept = y_mean - slope * x_mean

        r_squared = xy_sum_of_squares ** 2.0 / (xx_sum_of_squares * yy_sum_of_squares)

        [slope, intercept, r_squared]
    end

    # code taken from https://github.com/clbustos/statsample/blob/master/lib/statsample/regression/simple.rb#L74
    # (StatSample Ruby gem, simple linear regression.)
    def simple_regression_slope(x, y)
      raise "Trying to take the least-squares slope of two different-sized arrays!" if x.size != y.size

        x_mean = mean(x)
        y_mean = mean(y)

        num = den = 0.0
        (0...x.size).each do |i|
          num += (x[i] - x_mean) * (y[i] - y_mean)
            den += (x[i] - x_mean)**2.0
        end

        slope = num / den
        #intercept = y_mean - slope * x_mean

        slope
    end
  end
end
