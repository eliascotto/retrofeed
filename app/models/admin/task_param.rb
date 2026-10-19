module Admin
  class TaskParam
    INTEGER_REGEX = /\A-?\d+\z/
    UUID_REGEX = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

    attr_reader :name, :type, :required

    def initialize(name:, type: :string, required: true)
      @name = name.to_s
      @type = type.to_sym
      @required = required
    end

    # Returns [error_message_or_nil, coerced_value]
    def validate(raw_value)
      value = raw_value.to_s.strip

      if value.empty?
        if required
          [ "#{name} is required", nil ]
        else
          [ nil, nil ]
        end
      else
        case type
        when :uuid
          if value.match?(UUID_REGEX)
            [ nil, value ]
          else
            [ "#{name} must be an UUID", nil ]
          end
        when :integer
          if value.match?(INTEGER_REGEX)
            [ nil, value ]
          else
            [ "#{name} must be an integer", nil ]
          end
        else
          [ nil, value ]
        end
      end
    end

    def html_input_type
      type == :integer ? "number" : "text"
    end
  end
end
