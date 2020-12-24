module Ethereum

  class Encoder
    def encode(type, value, components)
      is_array, arity, array_subtype = Abi::parse_array_type(type)
      if is_array && arity
        encode_static_array(arity, array_subtype, value, components)
      elsif is_array
        encode_dynamic_array(array_subtype, value, components)
      else
        core, subtype = Abi::parse_type(type)
        if core == 'tuple'
          encode_tuple(value, components)
        else
          method_name = "encode_#{core}".to_sym
          self.send(method_name, value, subtype)
        end
      end
    end

    def encode_tuple(tuple_value, components)
      local_head = ""
      local_tail = ""
      component_args = tuple_value.values
      components.each.with_index do |component, component_index|
        encoded = encode(component['type'], component_args[component_index], nil)
        if encoded.is_a? Array
          local_head << encoded[0]
          local_tail << encoded[1]
        else
          local_head << encoded
        end
      end

      local_head + local_tail
    end

    def encode_static_array(arity, array_subtype, array, components)
      raise "Wrong number of arguments" if arity != array.size
      array.inject("") { |a, e| a << encode(array_subtype, e, components) }
    end

    def encode_dynamic_array(array_subtype, array, components)
      location = encode_uint(@inputs ? size_of_inputs(@inputs) + @tail.size/2 : 32)
      size = encode_uint(array.size)
      data = array.inject("") { |a, e| a << encode(array_subtype, e, components) }
      [location, size + data]
    end

    def encode_int(value, _ = nil)
      to_twos_complement(value).to_s(16).rjust(64, '0')
    end

    def encode_uint(value, _ = nil)
      raise ArgumentError if value < 0
      encode_int(value)
    end

    def encode_bool(value, _)
      (value ? "1" : "0").rjust(64, '0')
    end

    def encode_fixed(value, subtype)
      n = subtype.nil? ? 128 : /(\d+)x(\d+)/.match(subtype)[2].to_i
      do_encode_fixed(value, n)
    end

    def do_encode_fixed(value, n)
      encode_uint((value * 2**n).to_i)
    end

    def encode_ufixed(_value, _)
      raise NotImplementedError
    end

    def encode_bytes(value, subtype)
      subtype.nil? ? encode_dynamic_bytes(value) : encode_static_bytes(value)
    end

    def encode_static_bytes(value)
      value.bytes.map {|x| x.to_s(16).rjust(2, '0')}.join("").ljust(64, '0')
    end

    def encode_dynamic_bytes(value)
      location = encode_uint(@inputs ? size_of_inputs(@inputs) + @tail.size/2 : 32)
      size = encode_uint(value.size)
      content = encode_static_bytes(value)
      [location, size + content]
    end

    def encode_string(value, _)
      location = encode_uint(@inputs ? size_of_inputs(@inputs) + @tail.size/2 : 32)
      size = encode_uint(value.bytes.size)
      content = value.bytes.map {|x| x.to_s(16).rjust(2, '0')}.join("").ljust(64, '0')
      [location, size + content]
    end

    def encode_address(value, _)
      value = "0" * 24 + value.gsub(/^0x/,'')
      raise ArgumentError if value.size != 64
      value
    end

    def ensure_prefix(value)
      value.start_with?("0x") ? value : ("0x" + value)
    end

    def encode_arguments(inputs, args)
      raise "Wrong number of arguments" if inputs.length != args.length
      @head = ""
      @tail = ""
      @inputs = inputs
      inputs.each.with_index do |input, index|
        encoded = encode(input.type, args[index], input.components)
        if encoded.is_a? Array
          @head << encoded[0]
          @tail << encoded[1]
        else
          @head << encoded
        end
      end
      @head + @tail
    end

    private
      def to_twos_complement(number)
        (number & ((1 << 256) - 1))
      end

      def size_of_inputs(inputs)
        inputs.map do |input|
          _, arity, _ = Abi::parse_array_type(input.type)
          arity.nil? ? 32 : arity * 32
        end.inject(:+)
      end
  end

end
