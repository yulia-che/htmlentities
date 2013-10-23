class HTMLEntities
  InstructionError = Class.new(RuntimeError)

  class Encoder #:nodoc:
    INSTRUCTIONS = [:basic, :named, :decimal, :hexadecimal]

    def initialize(flavor, instructions)
      @flavor = flavor
      instructions = [:basic] if instructions.empty?
      validate_instructions(instructions)
      build_basic_entity_encoder(instructions)
      build_extended_entity_encoder(instructions)
    end

    def encode(source)
      post_process(
        prepare(source).
          gsub(basic_entity_regexp){ |match| encode_basic(match) }.
          gsub(extended_entity_regexp){ |match| encode_extended(match) }
      )
    end

  private

    def prepare(string) #:nodoc:
      string.to_s.encode(Encoding::UTF_8)
    end

    def post_process(string)
      if string.encoding != Encoding::ASCII && string.match(/\A[\x01-\x7F]*\z/)
        string.encode(Encoding::ASCII)
      else
        string
      end
    end

    def basic_entity_regexp
      @basic_entity_regexp ||= @flavor.match(/^html/) ? /[<>"&]/ : /[<>'"&]/
    end

    def extended_entity_regexp
      @extended_entity_regexp ||= (
        pattern = '[^\u{20}-\u{7E}]'
        pattern << "|'" if @flavor == 'html4'
        Regexp.new(pattern)
      )
    end

    def validate_instructions(instructions)
      unknown_instructions = instructions - INSTRUCTIONS
      if unknown_instructions.any?
        raise InstructionError, "unknown encode_entities command(s): #{unknown_instructions.inspect}"
      end

      if (instructions.include?(:decimal) && instructions.include?(:hexadecimal))
        raise InstructionError, "hexadecimal and decimal encoding are mutually exclusive"
      end
    end

    def build_basic_entity_encoder(instructions)
      if instructions.include?(:basic) || instructions.include?(:named)
        method = :encode_named
      elsif instructions.include?(:decimal)
        method = :encode_decimal
      elsif instructions.include?(:hexadecimal)
        method = :encode_hexadecimal
      end
      instance_eval "def encode_basic(char)\n#{method}(char)\nend"
    end

    def build_extended_entity_encoder(instructions)
      definition = "def encode_extended(char)\n"
      ([:named, :decimal, :hexadecimal] & instructions).each do |encoder|
        definition << "encoded = encode_#{encoder}(char)\n"
        definition << "return encoded if encoded\n"
      end
      definition << "char\n"
      definition << "end"
      instance_eval definition
    end

    def encode_named(char)
      cp = char.unpack('U')[0]
      (e = reverse_map[cp]) && "&#{e};"
    end

    def encode_decimal(char)
      "&##{char.unpack('U')[0]};"
    end

    def encode_hexadecimal(char)
      "&#x#{char.unpack('U')[0].to_s(16)};"
    end

    def reverse_map
      @reverse_map ||= (
        skips = HTMLEntities::SKIP_DUP_ENCODINGS[@flavor]
        map = HTMLEntities::MAPPINGS[@flavor]
        uniqmap = skips ? map.reject{|ent,hx| skips.include? ent} : map
        uniqmap.invert
      )
    end
  end
end
