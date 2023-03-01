module YJITMetrics
  module CLI
    def self.human_string_to_boolean(str)
      str = str.downcase
      yes_value = str["yes"] || str["1"] || str["t"] || false
      no_value = str["no"] || str["0"] || str["f"]

      unless yes_value || no_value
        raise "Couldn't figure out yes/no or true/false or 1/0 for boolean param: #{str.inspect}!"
      end

      if yes_value && no_value
        raise "Couldn't figure out JUST ONE of yes/no or true/false or 1/0 for boolean param: #{str.inspect}!"
      end

      yes_value
    end
  end
end
