# Generated from conformance/shell/draw_ops.zir by the zizek emitter. Do not edit by hand.
# frozen_string_literal: true

module ZizekDrawOps
  module_function

  def f64_from_bits(text)
    [text.to_i(16)].pack("Q<").unpack1("E")
  end

  def f64_to_bits(value)
    [value].pack("E").unpack1("Q<")
  end

  def alphabet_from_hex(text)
    return nil if text.empty?

    Zizek.alphabet([text].pack("H*").force_encoding(Encoding::UTF_8))
  end

  def trace_draw(test_case, op)
    head, *fields = op.split(":")
    case head
    when "i"
      value = test_case.integer(fields[0].to_i, fields[1].to_i)
      return "i:#{value}"
    when "b"
      value = test_case.boolean()
      return "b:#{value ? 1 : 0}"
    when "y"
      value = test_case.bytes(fields[0].to_i, fields[1].to_i)
      return "y:#{value.unpack1('H*')}"
    when "f"
      value = test_case.float(f64_from_bits(fields[0]), f64_from_bits(fields[1]))
      return format("f:%016x", f64_to_bits(value))
    when "s"
      value = test_case.string(fields[0].to_i, fields[1].to_i, alphabet: alphabet_from_hex(fields[2]))
      return "s:#{value.encode(Encoding::UTF_8).b.unpack1('H*')}"
    when "k"
      value = test_case.integer(fields[0].to_i, fields[1].to_i, key: fields[2].to_i(16))
      return "k:#{value}"
    when "l"
      value = test_case.__send__(:collect, Zizek::Generators.integers(min: fields[2].to_i, max: fields[3].to_i), fields[0].to_i, fields[1] == '-' ? nil : fields[1].to_i, 'list.element')
      return "l:#{value.join(',')}"
    when "q"
      value = test_case.__send__(:collect_unique, Zizek::Generators.integers(min: fields[2].to_i, max: fields[3].to_i), nil, fields[0].to_i, fields[1] == '-' ? nil : fields[1].to_i, 'set.element')
      return "q:#{value.join(',')}"
    when "c"
      value = test_case.clone_stream.integer(fields[0].to_i, fields[1].to_i)
      return "c:#{value}"
    else raise "unknown draw op #{head.inspect}"
    end
  end
end
