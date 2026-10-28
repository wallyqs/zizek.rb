# Generated from ZizekIR. Do not edit by hand.
module Zizek
  module Core
    MASK = (1 << 64) - 1
    module_function

    def rev64(value)
      result = 0
      64.times do
        result = ((result << 1) | (value & 1)) & MASK
        value >>= 1
      end
      result
    end

    def f2bits(value)
      [value].pack("E").unpack1("Q<")
    end

    def bits2f(value)
      [value].pack("Q<").unpack1("E")
    end

    def f64_to_u64(value)
      return 0 if value.nan? || value <= 0.0
      return MASK if value >= 18_446_744_073_709_551_616.0
      value.to_i
    end

    def u64_to_i64(value)
      value >= (1 << 63) ? value - (1 << 64) : value
    end

    def encode_exponent(biased_exp)
      c2047 = 2047
      is2047 = (biased_exp == c2047)
      if is2047
        return c2047
      end
      c1023 = 1023
      ge = (biased_exp >= c1023)
      if ge
        r = ((biased_exp - c1023) & MASK)
        return r
      end
      c2046 = 2046
      r2 = ((c2046 - biased_exp) & MASK)
      return r2
    end

    def decode_exponent(enc)
      c2047 = 2047
      is2047 = (enc == c2047)
      if is2047
        return c2047
      end
      c1023 = 1023
      le = (enc <= c1023)
      if le
        r = ((enc + c1023) & MASK)
        return r
      end
      c2046 = 2046
      r2 = ((c2046 - enc) & MASK)
      return r2
    end

    def reverse_bits_n(val, n)
      c0 = 0
      isz = (n == c0)
      if isz
        return c0
      end
      c64 = 64
      rev = rev64(val)
      sh = ((c64 - n) & MASK)
      r = (rev >> sh)
      return r
    end

    def update_mantissa(unbiased_exp, mantissa)
      zero_i = 0
      le0 = (unbiased_exp <= zero_i)
      if le0
        c52 = 52
        r = reverse_bits_n(mantissa, c52)
        return r
      end
      c51i = 51
      le51 = (unbiased_exp <= c51i)
      if le51
        c52i = 52
        nfi = (c52i - unbiased_exp)
        n_frac = (nfi & MASK)
        one = 1
        shifted = ((one << n_frac) & MASK)
        frac_mask = ((shifted - one) & MASK)
        frac = (mantissa & frac_mask)
        xored = (mantissa ^ frac)
        revfrac = reverse_bits_n(frac, n_frac)
        r = (xored | revfrac)
        return r
      end
      return mantissa
    end

    def is_simple_float(x)
      sb = (f2bits(x) >> 63) == 1
      inf = !x.infinite?.nil?
      nan = x.nan?
      sb_or_inf = (sb || inf)
      bad = (sb_or_inf || nan)
      false_ = false
      if bad
        return false_
      end
      pow56f = 72057594037927936.to_f
      ge = (x >= pow56f)
      if ge
        return false_
      end
      i = f64_to_u64(x)
      back = i.to_f
      eqv = (back == x)
      pow56 = 72057594037927936
      lt = (i < pow56)
      res = (eqv && lt)
      return res
    end

    def float_to_index(x)
      simple = is_simple_float(x)
      if simple
        si = f64_to_u64(x)
        return si
      end
      bits = f2bits(x)
      c52 = 52
      shr = (bits >> c52)
      c2047 = 2047
      biased_exp = (shr & c2047)
      mmask = 4503599627370495
      mantissa = (bits & mmask)
      be_i = u64_to_i64(biased_exp)
      c1023i = 1023
      unbiased_exp = (be_i - c1023i)
      mantissa_enc = update_mantissa(unbiased_exp, mantissa)
      exp_enc = encode_exponent(biased_exp)
      bit63 = 9223372036854775808
      expsh = ((exp_enc << c52) & MASK)
      hi = (bit63 | expsh)
      r = (hi | mantissa_enc)
      return r
    end

    def index_to_float(i)
      c63 = 63
      top = (i >> c63)
      c0 = 0
      isint = (top == c0)
      if isint
        m56 = 72057594037927935
        integral = (i & m56)
        f = integral.to_f
        return f
      end
      c52 = 52
      shr = (i >> c52)
      c2047 = 2047
      exp_enc = (shr & c2047)
      biased_exp = decode_exponent(exp_enc)
      mmask = 4503599627370495
      mantissa_enc = (i & mmask)
      be_i = u64_to_i64(biased_exp)
      c1023i = 1023
      unbiased_exp = (be_i - c1023i)
      mantissa = update_mantissa(unbiased_exp, mantissa_enc)
      besh = ((biased_exp << c52) & MASK)
      bitsr = (besh | mantissa)
      f2 = bits2f(bitsr)
      return f2
    end

    def min_reversed_in_range(lo, hi, n)
      zero_i = 0
      isz = (n == zero_i)
      c0 = 0
      if isz
        return c0
      end
      one = 1
      lop1 = ((lo + one) & MASK)
      k_lo = (lop1 >> one)
      k_hi = (hi >> one)
      le = (k_lo <= k_hi)
      if le
        onei = 1
        nm1 = (n - onei)
        rec = min_reversed_in_range(k_lo, k_hi, nm1)
        two = 2
        r = ((rec * two) & MASK)
        return r
      end
      return lo
    end

    def simplest_in_range(lo, hi)
      c = lo.ceil.to_f
      cle = (c <= hi)
      pow56f = 72057594037927936.to_f
      clt = (c < pow56f)
      inrange = (cle && clt)
      if inrange
        return c
      end
      lo_bits = f2bits(lo)
      hi_bits = f2bits(hi)
      c52 = 52
      e_lo = (lo_bits >> c52)
      e_hi = (hi_bits >> c52)
      mmask = 4503599627370495
      m_lo = (lo_bits & mmask)
      m_hi = (hi_bits & mmask)
      c1023 = 1023
      cond = (e_lo >= c1023)
      ncond = (!cond)
      e = e_lo
      m_min = m_lo
      m_max = m_hi
      eq_hilo = (e_hi == e_lo)
      ne_hilo = (!eq_hilo)
      if ne_hilo
        m_max = mmask
      end
      if ncond
        e = e_hi
        m_max = m_hi
        eq_lohi = (e_lo == e_hi)
        ne_lohi = (!eq_lohi)
        if ne_lohi
          zero = 0
          m_min = zero
        end
      end
      c1023i = 1023
      e_i = u64_to_i64(e)
      unbiased = (e_i - c1023i)
      c52i = 52
      ge52 = (unbiased >= c52i)
      if ge52
        esh0 = ((e << c52) & MASK)
        bitsr0 = (esh0 | m_min)
        f0 = bits2f(bitsr0)
        return f0
      end
      zero_i = 0
      le0 = (unbiased <= zero_i)
      n_frac = c52i
      nle0 = (!le0)
      if nle0
        sub = (c52i - unbiased)
        n_frac = sub
      end
      one = 1
      shl1 = ((one << n_frac) & MASK)
      low_mask = ((shl1 - one) & MASK)
      h = (m_min >> n_frac)
      l_lo = (m_min & low_mask)
      l_hi = (m_max & low_mask)
      minrev = min_reversed_in_range(l_lo, l_hi, n_frac)
      hsh = ((h << n_frac) & MASK)
      m_best = (hsh | minrev)
      esh = ((e << c52) & MASK)
      bitsr = (esh | m_best)
      f = bits2f(bitsr)
      return f
    end

    def base64_encode(data)
      alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".b
      out = String.new(encoding: Encoding::BINARY)
      n = data.bytesize
      i0 = 0
      i1 = 1
      i2 = 2
      i3 = 3
      u0 = 0
      c6 = 6
      c8 = 8
      c12 = 12
      c16 = 16
      c18 = 18
      c3f = 63
      eq = 61
      pos = i0
      loop do
        done = (pos >= n)
        if done
          break
        end
        rem = (n - pos)
        b0 = data.getbyte(pos)
        b1 = u0
        b2 = u0
        has1 = (rem > i1)
        if has1
          p1 = (pos + i1)
          b1 = data.getbyte(p1)
        end
        has2 = (rem > i2)
        if has2
          p2 = (pos + i2)
          b2 = data.getbyte(p2)
        end
        s16 = ((b0 << c16) & MASK)
        s8 = ((b1 << c8) & MASK)
        acc0 = (s16 | s8)
        acc = (acc0 | b2)
        t0 = (acc >> c18)
        k0 = (t0 & c3f)
        d0 = alphabet.getbyte(k0)
        out << (d0 & 0xff)
        t1 = (acc >> c12)
        k1 = (t1 & c3f)
        d1 = alphabet.getbyte(k1)
        out << (d1 & 0xff)
        d2 = eq
        if has1
          t2 = (acc >> c6)
          k2 = (t2 & c3f)
          d2 = alphabet.getbyte(k2)
        end
        out << (d2 & 0xff)
        d3 = eq
        if has2
          k3 = (acc & c3f)
          d3 = alphabet.getbyte(k3)
        end
        out << (d3 & 0xff)
        pos = (pos + i3)
      end
      return out
    end

    def base64_value(c)
      a_upper = 65
      z_upper = 90
      a_lower = 97
      z_lower = 122
      zero = 48
      nine = 57
      plus = 43
      slash = 47
      c26 = 26
      c52 = 52
      c62 = 62
      c63 = 63
      invalid = 64
      value = invalid
      upper_lo = (c >= a_upper)
      upper_hi = (c <= z_upper)
      is_upper = (upper_lo && upper_hi)
      if is_upper
        value = ((c - a_upper) & MASK)
      end
      lower_lo = (c >= a_lower)
      lower_hi = (c <= z_lower)
      is_lower = (lower_lo && lower_hi)
      if is_lower
        lower_offset = ((c - a_lower) & MASK)
        value = ((lower_offset + c26) & MASK)
      end
      digit_lo = (c >= zero)
      digit_hi = (c <= nine)
      is_digit = (digit_lo && digit_hi)
      if is_digit
        digit_offset = ((c - zero) & MASK)
        value = ((digit_offset + c52) & MASK)
      end
      is_plus = (c == plus)
      if is_plus
        value = c62
      end
      is_slash = (c == slash)
      if is_slash
        value = c63
      end
      return value
    end

    def base64_decode(data)
      out = String.new(encoding: Encoding::BINARY)
      none = nil
      n = data.bytesize
      i0 = 0
      i1 = 1
      i2 = 2
      i3 = 3
      i4 = 4
      u0 = 0
      u6 = 6
      u8 = 8
      u12 = 12
      u16 = 16
      u18 = 18
      invalid_value = 64
      padding = 61
      rem = n
      loop do
        short_ = (rem < i4)
        if short_
          break
        end
        rem = (rem - i4)
      end
      bad_length = (rem != i0)
      if bad_length
        return none
      end
      pos = i0
      loop do
        done = (pos >= n)
        if done
          break
        end
        p1 = (pos + i1)
        p2 = (pos + i2)
        p3 = (pos + i3)
        next_ = (pos + i4)
        last = (next_ == n)
        b0 = data.getbyte(pos)
        b1 = data.getbyte(p1)
        b2 = data.getbyte(p2)
        b3 = data.getbyte(p3)
        c0 = base64_value(b0)
        c1 = base64_value(b1)
        bad_c0 = (c0 >= invalid_value)
        if bad_c0
          return none
        end
        bad_c1 = (c1 >= invalid_value)
        if bad_c1
          return none
        end
        pad2 = (b2 == padding)
        pad3 = (b3 == padding)
        any_padding = (pad2 || pad3)
        not_last = (!last)
        padding_before_tail = (any_padding && not_last)
        if padding_before_tail
          return none
        end
        not_pad3 = (!pad3)
        bad_padding = (pad2 && not_pad3)
        if bad_padding
          return none
        end
        c2 = u0
        not_pad2 = (!pad2)
        if not_pad2
          c2 = base64_value(b2)
          bad_c2 = (c2 >= invalid_value)
          if bad_c2
            return none
          end
        end
        c3 = u0
        if not_pad3
          c3 = base64_value(b3)
          bad_c3 = (c3 >= invalid_value)
          if bad_c3
            return none
          end
        end
        s18 = ((c0 << u18) & MASK)
        s12 = ((c1 << u12) & MASK)
        s6 = ((c2 << u6) & MASK)
        acc0 = (s18 | s12)
        acc1 = (acc0 | s6)
        acc = (acc1 | c3)
        out0 = (acc >> u16)
        out << (out0 & 0xff)
        if not_pad2
          out1 = (acc >> u8)
          out << (out1 & 0xff)
        end
        if not_pad3
          out << (acc & 0xff)
        end
        pos = next_
      end
      some = out.dup
      return some
    end

    def u64_as_i64(value)
      signed_ = u64_to_i64(value)
      return signed_
    end

    def twos_complement_le(data)
      out = String.new(encoding: Encoding::BINARY)
      n = data.bytesize
      i0 = 0
      i1 = 1
      u1 = 1
      u255 = 255
      carry = true
      pos = i0
      loop do
        done = (pos >= n)
        if done
          break
        end
        byte_ = data.getbyte(pos)
        inverted = (byte_ ^ u255)
        sum = inverted
        if carry
          sum = ((inverted + u1) & MASK)
          carry = (sum > u255)
        end
        out << (sum & 0xff)
        pos = (pos + i1)
      end
      return out
    end

    def canonicalize_signed_le(data)
      out = String.new(encoding: Encoding::BINARY)
      n = data.bytesize
      i0 = 0
      i1 = 1
      i2 = 2
      u0 = 0
      u128 = 128
      u255 = 255
      empty = (n == i0)
      if empty
        out << (u0 & 0xff)
        return out
      end
      keep = n
      loop do
        one_left = (keep <= i1)
        if one_left
          break
        end
        last_pos = (keep - i1)
        prev_pos = (keep - i2)
        last = data.getbyte(last_pos)
        prev = data.getbyte(prev_pos)
        prev_sign = (prev & u128)
        prev_negative = (prev_sign != u0)
        prev_positive = (!prev_negative)
        last_zero = (last == u0)
        last_ff = (last == u255)
        positive_extension = (last_zero && prev_positive)
        negative_extension = (last_ff && prev_negative)
        redundant = (positive_extension || negative_extension)
        needed = (!redundant)
        if needed
          break
        end
        keep = (keep - i1)
      end
      pos = i0
      loop do
        done = (pos >= keep)
        if done
          break
        end
        byte_ = data.getbyte(pos)
        out << (byte_ & 0xff)
        pos = (pos + i1)
      end
      return out
    end

    def signed_abs_le(data)
      value = canonicalize_signed_le(data)
      n = value.bytesize
      i0 = 0
      i1 = 1
      u0 = 0
      u128 = 128
      last_pos = (n - i1)
      last = value.getbyte(last_pos)
      sign = (last & u128)
      negative = (sign != u0)
      positive = (!negative)
      if positive
        return value
      end
      magnitude = twos_complement_le(value)
      out = String.new(encoding: Encoding::BINARY)
      pos = i0
      loop do
        done = (pos >= n)
        if done
          break
        end
        byte_ = magnitude.getbyte(pos)
        out << (byte_ & 0xff)
        pos = (pos + i1)
      end
      mag_last = magnitude.getbyte(last_pos)
      mag_sign = (mag_last & u128)
      needs_zero = (mag_sign != u0)
      if needs_zero
        out << (u0 & 0xff)
      end
      return out
    end

    def signed_negate_le(data)
      value = canonicalize_signed_le(data)
      out = String.new(encoding: Encoding::BINARY)
      n = value.bytesize
      i0 = 0
      i1 = 1
      u0 = 0
      u128 = 128
      u255 = 255
      last_pos = (n - i1)
      last = value.getbyte(last_pos)
      sign = (last & u128)
      negative = (sign != u0)
      extension = u0
      if negative
        extension = u255
      end
      pos = i0
      loop do
        done = (pos >= n)
        if done
          break
        end
        byte_ = value.getbyte(pos)
        out << (byte_ & 0xff)
        pos = (pos + i1)
      end
      out << (extension & 0xff)
      negated = twos_complement_le(out)
      canonical = canonicalize_signed_le(negated)
      return canonical
    end

    def signed_add_le(left_raw, right_raw)
      left = canonicalize_signed_le(left_raw)
      right = canonicalize_signed_le(right_raw)
      out = String.new(encoding: Encoding::BINARY)
      left_n = left.bytesize
      right_n = right.bytesize
      i0 = 0
      i1 = 1
      u0 = 0
      u8 = 8
      u128 = 128
      u255 = 255
      left_last_pos = (left_n - i1)
      right_last_pos = (right_n - i1)
      left_last = left.getbyte(left_last_pos)
      right_last = right.getbyte(right_last_pos)
      left_sign = (left_last & u128)
      right_sign = (right_last & u128)
      left_negative = (left_sign != u0)
      right_negative = (right_sign != u0)
      left_extension = u0
      if left_negative
        left_extension = u255
      end
      right_extension = u0
      if right_negative
        right_extension = u255
      end
      width = left_n
      right_longer = (right_n > left_n)
      if right_longer
        width = right_n
      end
      width = (width + i1)
      carry = u0
      pos = i0
      loop do
        done = (pos >= width)
        if done
          break
        end
        left_byte = left_extension
        left_present = (pos < left_n)
        if left_present
          left_byte = left.getbyte(pos)
        end
        right_byte = right_extension
        right_present = (pos < right_n)
        if right_present
          right_byte = right.getbyte(pos)
        end
        partial = ((left_byte + right_byte) & MASK)
        sum = ((partial + carry) & MASK)
        out_byte = (sum & u255)
        out << (out_byte & 0xff)
        carry = (sum >> u8)
        pos = (pos + i1)
      end
      canonical = canonicalize_signed_le(out)
      return canonical
    end

    def signed_sub_le(left, right)
      negative_right = signed_negate_le(right)
      result = signed_add_le(left, negative_right)
      return result
    end

    def positive_shr1_le(data)
      value = canonicalize_signed_le(data)
      out = String.new(encoding: Encoding::BINARY)
      n = value.bytesize
      i0 = 0
      i1 = 1
      u1 = 1
      u7 = 7
      pos = i0
      loop do
        done = (pos >= n)
        if done
          break
        end
        current = value.getbyte(pos)
        shifted = (current >> u1)
        out_byte = shifted
        next_pos = (pos + i1)
        has_next = (next_pos < n)
        if has_next
          next_ = value.getbyte(next_pos)
          next_low = (next_ & u1)
          incoming = ((next_low << u7) & MASK)
          out_byte = (shifted | incoming)
        end
        out << (out_byte & 0xff)
        pos = next_pos
      end
      canonical = canonicalize_signed_le(out)
      return canonical
    end

    def signed_mul_le(left_raw, right_raw)
      left_value = canonicalize_signed_le(left_raw)
      right_value = canonicalize_signed_le(right_raw)
      left_n = left_value.bytesize
      right_n = right_value.bytesize
      i1 = 1
      u0 = 0
      u1 = 1
      u128 = 128
      left_last_pos = (left_n - i1)
      right_last_pos = (right_n - i1)
      left_last = left_value.getbyte(left_last_pos)
      right_last = right_value.getbyte(right_last_pos)
      left_sign = (left_last & u128)
      right_sign = (right_last & u128)
      left_negative = (left_sign != u0)
      right_negative = (right_sign != u0)
      negative_result = (left_negative != right_negative)
      multiplicand = signed_abs_le(left_value)
      multiplier = signed_abs_le(right_value)
      product = String.new(encoding: Encoding::BINARY)
      product << (u0 & 0xff)
      loop do
        low = multiplier.getbyte(u0)
        nonzero = (low != u0)
        multiplier_n = multiplier.bytesize
        more_bytes = (multiplier_n > i1)
        has_value = (nonzero || more_bytes)
        done = (!has_value)
        if done
          break
        end
        low_bit = (low & u1)
        odd = (low_bit != u0)
        if odd
          product = signed_add_le(product, multiplicand)
        end
        multiplicand = signed_add_le(multiplicand, multiplicand)
        multiplier = positive_shr1_le(multiplier)
      end
      if negative_result
        product = signed_negate_le(product)
      end
      return product
    end

    def positive_div_le_nonzero(dividend_raw, divisor_raw)
      remainder = signed_abs_le(dividend_raw)
      scaled_divisor = signed_abs_le(divisor_raw)
      i0 = 0
      i1 = 1
      u0 = 0
      u1 = 1
      quotient = String.new(encoding: Encoding::BINARY)
      quotient << (u0 & 0xff)
      bit = String.new(encoding: Encoding::BINARY)
      bit << (u1 & 0xff)
      loop do
        scale_cmp = signed_compare_le(scaled_divisor, remainder)
        can_scale = (scale_cmp <= i0)
        stop_scaling = (!can_scale)
        if stop_scaling
          break
        end
        scaled_divisor = signed_add_le(scaled_divisor, scaled_divisor)
        bit = signed_add_le(bit, bit)
      end
      loop do
        scaled_divisor = positive_shr1_le(scaled_divisor)
        bit = positive_shr1_le(bit)
        bit_low = bit.getbyte(u0)
        bit_n = bit.bytesize
        bit_nonzero = (bit_low != u0)
        bit_more = (bit_n > i1)
        has_bit = (bit_nonzero || bit_more)
        done = (!has_bit)
        if done
          break
        end
        cmp = signed_compare_le(scaled_divisor, remainder)
        can_subtract = (cmp <= i0)
        if can_subtract
          remainder = signed_sub_le(remainder, scaled_divisor)
          quotient = signed_add_le(quotient, bit)
        end
      end
      return quotient
    end

    def positive_rem_le_nonzero(dividend, divisor)
      positive_dividend = signed_abs_le(dividend)
      positive_divisor = signed_abs_le(divisor)
      quotient = positive_div_le_nonzero(positive_dividend, positive_divisor)
      product = signed_mul_le(quotient, positive_divisor)
      remainder = signed_sub_le(positive_dividend, product)
      return remainder
    end

    def positive_pow_le(base_raw, exponent)
      u0 = 0
      u1 = 1
      result = String.new(encoding: Encoding::BINARY)
      result << (u1 & 0xff)
      factor = signed_abs_le(base_raw)
      power = exponent
      loop do
        done = (power == u0)
        if done
          break
        end
        low_bit = (power & u1)
        odd = (low_bit != u0)
        if odd
          result = signed_mul_le(result, factor)
        end
        factor = signed_mul_le(factor, factor)
        power = (power >> u1)
      end
      return result
    end

    def signed_compare_le(left_raw, right_raw)
      left = canonicalize_signed_le(left_raw)
      right = canonicalize_signed_le(right_raw)
      i0 = 0
      i1 = 1
      u0 = 0
      u128 = 128
      negative_one = (i0 - i1)
      left_n = left.bytesize
      right_n = right.bytesize
      left_last_pos = (left_n - i1)
      right_last_pos = (right_n - i1)
      left_last = left.getbyte(left_last_pos)
      right_last = right.getbyte(right_last_pos)
      left_sign = (left_last & u128)
      right_sign = (right_last & u128)
      left_negative = (left_sign != u0)
      right_negative = (right_sign != u0)
      right_positive = (!right_negative)
      left_only_negative = (left_negative && right_positive)
      if left_only_negative
        return negative_one
      end
      left_positive = (!left_negative)
      right_only_negative = (left_positive && right_negative)
      if right_only_negative
        return i1
      end
      left_shorter = (left_n < right_n)
      if left_shorter
        short_result = negative_one
        if left_negative
          short_result = i1
        end
        return short_result
      end
      left_longer = (left_n > right_n)
      if left_longer
        long_result = i1
        if left_negative
          long_result = negative_one
        end
        return long_result
      end
      pos = left_n
      loop do
        done = (pos == i0)
        if done
          break
        end
        pos = (pos - i1)
        left_byte = left.getbyte(pos)
        right_byte = right.getbyte(pos)
        byte_less = (left_byte < right_byte)
        if byte_less
          return negative_one
        end
        byte_greater = (left_byte > right_byte)
        if byte_greater
          return i1
        end
      end
      return i0
    end

    def bigint_zero()
      out = String.new(encoding: Encoding::BINARY)
      zero = 0
      out << (zero & 0xff)
      return out
    end

    def bigint_one()
      out = String.new(encoding: Encoding::BINARY)
      one = 1
      out << (one & 0xff)
      return out
    end

    def bigint_two()
      out = String.new(encoding: Encoding::BINARY)
      two = 2
      out << (two & 0xff)
      return out
    end

    def bigint_base_256()
      out = String.new(encoding: Encoding::BINARY)
      zero = 0
      one = 1
      out << (zero & 0xff)
      out << (one & 0xff)
      return out
    end

    def positive_u8_le(value)
      out = String.new(encoding: Encoding::BINARY)
      u0 = 0
      u128 = 128
      out << (value & 0xff)
      needs_sign_byte = (value >= u128)
      if needs_sign_byte
        out << (u0 & 0xff)
      end
      return out
    end

    def bigint_min(left, right)
      cmp = signed_compare_le(left, right)
      i0 = 0
      left_is_min = (cmp <= i0)
      if left_is_min
        out_left = canonicalize_signed_le(left)
        return out_left
      end
      out_right = canonicalize_signed_le(right)
      return out_right
    end

    def integer_simplest(min_value, max_value, shrink_towards)
      i0 = 0
      below_cmp = signed_compare_le(shrink_towards, min_value)
      below = (below_cmp < i0)
      if below
        min_out = canonicalize_signed_le(min_value)
        return min_out
      end
      above_cmp = signed_compare_le(shrink_towards, max_value)
      above = (above_cmp > i0)
      if above
        max_out = canonicalize_signed_le(max_value)
        return max_out
      end
      target_out = canonicalize_signed_le(shrink_towards)
      return target_out
    end

    def integer_validate(min_value, max_value, value)
      i0 = 0
      min_cmp = signed_compare_le(min_value, value)
      max_cmp = signed_compare_le(value, max_value)
      above_min = (min_cmp <= i0)
      below_max = (max_cmp <= i0)
      valid = (above_min && below_max)
      return valid
    end

    def integer_unit(min_value, max_value, shrink_towards)
      simplest = integer_simplest(min_value, max_value, shrink_towards)
      one = bigint_one()
      successor = signed_add_le(simplest, one)
      successor_valid = integer_validate(min_value, max_value, successor)
      if successor_valid
        return successor
      end
      predecessor = signed_sub_le(simplest, one)
      predecessor_valid = integer_validate(min_value, max_value, predecessor)
      if predecessor_valid
        return predecessor
      end
      return simplest
    end

    def integer_max_index(min_value, max_value)
      difference = signed_sub_le(max_value, min_value)
      out = signed_abs_le(difference)
      return out
    end

    def integer_to_index(min_value, max_value, shrink_towards, value)
      i0 = 0
      simplest = integer_simplest(min_value, max_value, shrink_towards)
      value_cmp = signed_compare_le(value, simplest)
      at_simplest = (value_cmp == i0)
      if at_simplest
        zero = bigint_zero()
        return zero
      end
      above_delta = signed_sub_le(max_value, simplest)
      above = signed_abs_le(above_delta)
      below_delta = signed_sub_le(simplest, min_value)
      below = signed_abs_le(below_delta)
      value_delta = signed_sub_le(value, simplest)
      distance = signed_abs_le(value_delta)
      one = bigint_one()
      distance_minus_one = signed_sub_le(distance, one)
      count_above = bigint_min(distance_minus_one, above)
      count_below = bigint_min(distance_minus_one, below)
      count = signed_add_le(count_above, count_below)
      value_above = (value_cmp > i0)
      if value_above
        up_index = signed_add_le(count, one)
        return up_index
      end
      distance_cmp = signed_compare_le(distance, above)
      up_slot_exists = (distance_cmp <= i0)
      if up_slot_exists
        count = signed_add_le(count, one)
      end
      down_index = signed_add_le(count, one)
      return down_index
    end

    def integer_from_index(min_value, max_value, shrink_towards, index_raw)
      i0 = 0
      simplest = integer_simplest(min_value, max_value, shrink_towards)
      index = signed_abs_le(index_raw)
      zero = bigint_zero()
      index_zero_cmp = signed_compare_le(index, zero)
      at_zero = (index_zero_cmp == i0)
      if at_zero
        some_simplest = simplest.dup
        return some_simplest
      end
      above_delta = signed_sub_le(max_value, simplest)
      above = signed_abs_le(above_delta)
      below_delta = signed_sub_le(simplest, min_value)
      below = signed_abs_le(below_delta)
      max_index = signed_add_le(above, below)
      past_cmp = signed_compare_le(index, max_index)
      past_end = (past_cmp > i0)
      if past_end
        none = nil
        return none
      end
      a = bigint_min(above, below)
      two_a = signed_add_le(a, a)
      two_a_cmp = signed_compare_le(index, two_a)
      interleaved = (two_a_cmp <= i0)
      distance = index.dup
      up = false
      if interleaved
        one = bigint_one()
        two = bigint_two()
        index_plus_one = signed_add_le(index, one)
        distance = positive_div_le_nonzero(index_plus_one, two)
        parity = positive_rem_le_nonzero(index, two)
        parity_cmp = signed_compare_le(parity, zero)
        up = (parity_cmp != i0)
      end
      tail = (!interleaved)
      if tail
        distance = signed_sub_le(index, a)
        range_cmp = signed_compare_le(above, below)
        up = (range_cmp > i0)
      end
      result = signed_sub_le(simplest, distance)
      if up
        result = signed_add_le(simplest, distance)
      end
      some = result.dup
      return some
    end

    def integer_shrink_extra_divisor(slot)
      u0 = 0
      u1 = 1
      u2 = 2
      u3 = 3
      u5 = 5
      u7 = 7
      u10 = 10
      divisor = u10
      is_three = (slot == u0)
      if is_three
        divisor = u3
      end
      is_five = (slot == u1)
      if is_five
        divisor = u5
      end
      is_seven = (slot == u2)
      if is_seven
        divisor = u7
      end
      out = positive_u8_le(divisor)
      return out
    end

    def integer_trailing_power(distance, radix)
      i0 = 0
      base = positive_u8_le(radix)
      zero = bigint_zero()
      power = bigint_one()
      rest = signed_abs_le(distance)
      loop do
        rest_cmp = signed_compare_le(rest, zero)
        exhausted = (rest_cmp == i0)
        if exhausted
          break
        end
        remainder = positive_rem_le_nonzero(rest, base)
        remainder_cmp = signed_compare_le(remainder, zero)
        divides = (remainder_cmp == i0)
        stops = (!divides)
        if stops
          break
        end
        rest = positive_div_le_nonzero(rest, base)
        power = signed_mul_le(power, base)
      end
      return power
    end

    def integer_shrink_extra_distance(distance, slot)
      i0 = 0
      u0 = 0
      u1 = 1
      u2 = 2
      u4 = 4
      u10 = 10
      zero = bigint_zero()
      one = bigint_one()
      divides = (slot < u4)
      if divides
        divisor = integer_shrink_extra_divisor(slot)
        quotient = positive_div_le_nonzero(distance, divisor)
        return quotient
      end
      radix = u2
      decimal = (slot == u4)
      if decimal
        radix = u10
      end
      power = integer_trailing_power(distance, radix)
      one_cmp = signed_compare_le(power, one)
      trivial = (one_cmp <= i0)
      if trivial
        return zero
      end
      whole_cmp = signed_compare_le(power, distance)
      whole = (whole_cmp >= i0)
      if whole
        return zero
      end
      earlier = u0
      loop do
        checked = (earlier >= u4)
        if checked
          break
        end
        earlier_divisor = integer_shrink_extra_divisor(earlier)
        earlier_quotient = positive_div_le_nonzero(distance, earlier_divisor)
        same_cmp = signed_compare_le(power, earlier_quotient)
        same = (same_cmp == i0)
        if same
          return zero
        end
        earlier = ((earlier + u1) & MASK)
      end
      return power
    end

    def integer_shrink_extra(min_value, max_value, shrink_towards, value, ordinal)
      i0 = 0
      u0 = 0
      u1 = 1
      u2 = 2
      u5 = 5
      u6 = 6
      zero = bigint_zero()
      prefix = positive_u8_le(u5)
      simplest = integer_simplest(min_value, max_value, shrink_towards)
      offset = signed_sub_le(value, simplest)
      distance = signed_abs_le(offset)
      seen = u0
      slot = u0
      loop do
        slots_done = (slot >= u6)
        if slots_done
          break
        end
        moved = integer_shrink_extra_distance(distance, slot)
        moved_cmp = signed_compare_le(moved, zero)
        moves = (moved_cmp > i0)
        if moves
          side = u0
          loop do
            sides_done = (side >= u2)
            if sides_done
              break
            end
            candidate = signed_add_le(simplest, moved)
            below = (side == u1)
            if below
              candidate = signed_sub_le(simplest, moved)
            end
            valid = integer_validate(min_value, max_value, candidate)
            if valid
              index = integer_to_index(min_value, max_value, shrink_towards, candidate)
              index_cmp = signed_compare_le(index, prefix)
              unprobed = (index_cmp >= i0)
              if unprobed
                wanted = (seen == ordinal)
                if wanted
                  some = candidate.dup
                  return some
                end
                seen = ((seen + u1) & MASK)
              end
            end
            side = ((side + u1) & MASK)
          end
        end
        slot = ((slot + u1) & MASK)
      end
      none = nil
      return none
    end

    def boolean_max_index()
      one = bigint_one()
      return one
    end

    def boolean_to_index(value)
      if value
        one = bigint_one()
        return one
      end
      zero = bigint_zero()
      return zero
    end

    def boolean_from_index(index)
      i0 = 0
      zero = bigint_zero()
      zero_cmp = signed_compare_le(index, zero)
      is_zero = (zero_cmp == i0)
      if is_zero
        false_ = false
        some_false = false_
        return some_false
      end
      one = bigint_one()
      one_cmp = signed_compare_le(index, one)
      is_one = (one_cmp == i0)
      if is_one
        true_ = true
        some_true = true_
        return some_true
      end
      none = nil
      return none
    end

    def bytes_simplest(min_size)
      out = String.new(encoding: Encoding::BINARY)
      i0 = 0
      i1 = 1
      u0 = 0
      pos = i0
      loop do
        done = (pos >= min_size)
        if done
          break
        end
        out << (u0 & 0xff)
        pos = (pos + i1)
      end
      return out
    end

    def bytes_unit(min_size, max_size)
      out = String.new(encoding: Encoding::BINARY)
      i0 = 0
      i1 = 1
      u0 = 0
      u1 = 1
      has_minimum = (min_size > i0)
      if has_minimum
        last_pos = (min_size - i1)
        pos = i0
        loop do
          done = (pos >= min_size)
          if done
            break
          end
          is_last = (pos == last_pos)
          byte_ = u0
          if is_last
            byte_ = u1
          end
          out << (byte_ & 0xff)
          pos = (pos + i1)
        end
        return out
      end
      has_values = (max_size > i0)
      if has_values
        out << (u1 & 0xff)
      end
      return out
    end

    def bytes_validate(min_size, max_size, value)
      length = value.bytesize
      above_min = (length >= min_size)
      below_max = (length <= max_size)
      valid = (above_min && below_max)
      return valid
    end

    def bytes_to_index(min_size, value)
      i0 = 0
      i1 = 1
      base = bigint_base_256()
      offset = bigint_zero()
      length = min_size
      value_length = value.bytesize
      loop do
        done = (length >= value_length)
        if done
          break
        end
        exponent = (length & MASK)
        bucket = positive_pow_le(base, exponent)
        offset = signed_add_le(offset, bucket)
        length = (length + i1)
      end
      position = bigint_zero()
      pos = i0
      loop do
        done = (pos >= value_length)
        if done
          break
        end
        byte_ = value.getbyte(pos)
        digit = positive_u8_le(byte_)
        shifted = signed_mul_le(position, base)
        position = signed_add_le(shifted, digit)
        pos = (pos + i1)
      end
      index = signed_add_le(offset, position)
      return index
    end

    def bytes_max_index(min_size, max_size)
      last = String.new(encoding: Encoding::BINARY)
      i0 = 0
      i1 = 1
      u255 = 255
      pos = i0
      loop do
        done = (pos >= max_size)
        if done
          break
        end
        last << (u255 & 0xff)
        pos = (pos + i1)
      end
      index = bytes_to_index(min_size, last)
      return index
    end

    def bytes_from_index(min_size, max_size, index_raw)
      i0 = 0
      i1 = 1
      base = bigint_base_256()
      remaining = signed_abs_le(index_raw)
      length = min_size
      loop do
        past_end = (length > max_size)
        if past_end
          break
        end
        exponent = (length & MASK)
        bucket = positive_pow_le(base, exponent)
        bucket_cmp = signed_compare_le(remaining, bucket)
        inside_bucket = (bucket_cmp < i0)
        if inside_bucket
          out = String.new(encoding: Encoding::BINARY)
          empty = (length == i0)
          if empty
            some_empty = out.dup
            return some_empty
          end
          power = (length - i1)
          power_u64 = (power & MASK)
          divisor = positive_pow_le(base, power_u64)
          pos = i0
          loop do
            done = (pos >= length)
            if done
              break
            end
            digit = positive_div_le_nonzero(remaining, divisor)
            byte_ = digit.getbyte(i0)
            out << (byte_ & 0xff)
            remaining = positive_rem_le_nonzero(remaining, divisor)
            divisor = positive_div_le_nonzero(divisor, base)
            pos = (pos + i1)
          end
          some = out.dup
          return some
        end
        remaining = signed_sub_le(remaining, bucket)
        length = (length + i1)
      end
      none = nil
      return none
    end

    def f64_abs(value)
      mask = 9223372036854775807
      bits = f2bits(value)
      cleared = (bits & mask)
      out = bits2f(cleared)
      return out
    end

    def f64_neg(value)
      mask = 9223372036854775808
      bits = f2bits(value)
      flipped = (bits ^ mask)
      out = bits2f(flipped)
      return out
    end

    def f64_infinity()
      bits = 9218868437227405312
      out = bits2f(bits)
      return out
    end

    def f64_neg_infinity()
      positive = f64_infinity()
      out = f64_neg(positive)
      return out
    end

    def f64_nan()
      bits = 9221120237041090560
      out = bits2f(bits)
      return out
    end

    def f64_max()
      bits = 9218868437227405311
      out = bits2f(bits)
      return out
    end

    def sign_aware_lte(left, right)
      zero = 0.to_f
      left_zero = (left == zero)
      right_zero = (right == zero)
      both_zero = (left_zero && right_zero)
      if both_zero
        left_negative = (f2bits(left) >> 63) == 1
        right_negative = (f2bits(right) >> 63) == 1
        left_positive = (!left_negative)
        only_right_negative = (left_positive && right_negative)
        ordered = (!only_right_negative)
        return ordered
      end
      ordered = (left <= right)
      return ordered
    end

    def float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, value)
      false_ = false
      true_ = true
      is_nan = value.nan?
      if is_nan
        return allow_nan
      end
      is_infinite = !value.infinite?.nil?
      if is_infinite
        no_infinity = (!allow_infinity)
        if no_infinity
          return false_
        end
        negative_infinity = f64_neg_infinity()
        is_negative_infinity = (value == negative_infinity)
        min_bounded = (min_value > negative_infinity)
        reject_low = (is_negative_infinity && min_bounded)
        if reject_low
          return false_
        end
        positive_infinity = f64_infinity()
        is_positive_infinity = (value == positive_infinity)
        max_bounded = (max_value < positive_infinity)
        reject_high = (is_positive_infinity && max_bounded)
        if reject_high
          return false_
        end
        return true_
      end
      zero = 0.to_f
      nonzero = (value != zero)
      magnitude = f64_abs(value)
      below_smallest = (magnitude < smallest_nonzero)
      reject_tiny = (nonzero && below_smallest)
      if reject_tiny
        return false_
      end
      above_min = sign_aware_lte(min_value, value)
      below_max = sign_aware_lte(value, max_value)
      valid = (above_min && below_max)
      return valid
    end

    def float_simplest(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero)
      zero = 0.to_f
      zero_ok = float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, zero)
      if zero_ok
        found = zero
        return found
      end
      negative_zero = f64_neg(zero)
      negative_zero_ok = float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, negative_zero)
      if negative_zero_ok
        found = negative_zero
        return found
      end
      has_best = false
      best_index = 0
      best_value = zero
      largest = f64_max()
      max_positive = (max_value > zero)
      if max_positive
        low = min_value
        min_below_smallest = (min_value < smallest_nonzero)
        if min_below_smallest
          low = smallest_nonzero
        end
        high = max_value
        max_above_largest = (max_value > largest)
        if max_above_largest
          high = largest
        end
        ordered = (low <= high)
        if ordered
          candidate = simplest_in_range(low, high)
          index = float_to_index(candidate)
          has_best = true
          best_index = index
          best_value = candidate
        end
      end
      min_negative = (min_value < zero)
      if min_negative
        mirrored_low = f64_neg(max_value)
        low = mirrored_low
        mirror_below_smallest = (mirrored_low < smallest_nonzero)
        if mirror_below_smallest
          low = smallest_nonzero
        end
        mirrored_high = f64_neg(min_value)
        high = mirrored_high
        mirror_above_largest = (mirrored_high > largest)
        if mirror_above_largest
          high = largest
        end
        ordered = (low <= high)
        if ordered
          candidate = simplest_in_range(low, high)
          index = float_to_index(candidate)
          no_best = (!has_best)
          strictly_lower = (index < best_index)
          take = (no_best || strictly_lower)
          if take
            negated = f64_neg(candidate)
            has_best = true
            best_index = index
            best_value = negated
          end
        end
      end
      if has_best
        found = best_value
        return found
      end
      if allow_infinity
        positive_infinity = f64_infinity()
        positive_ok = float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, positive_infinity)
        if positive_ok
          found = positive_infinity
          return found
        end
        negative_infinity = f64_neg_infinity()
        negative_ok = float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, negative_infinity)
        if negative_ok
          found = negative_infinity
          return found
        end
      end
      if allow_nan
        not_a_number = f64_nan()
        found = not_a_number
        return found
      end
      missing = nil
      return missing
    end

    def float_unit(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero)
      simplest_opt = float_simplest(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero)
      present = !simplest_opt.nil?
      absent = (!present)
      if absent
        missing = nil
        return missing
      end
      simplest = simplest_opt
      simplest_is_nan = simplest.nan?
      if simplest_is_nan
        found = simplest
        return found
      end
      u1 = 1
      u4 = 4
      magnitude = f64_abs(simplest)
      base = float_to_index(magnitude)
      offset = u1
      loop do
        exhausted = (offset >= u4)
        if exhausted
          break
        end
        index = ((base + offset) & MASK)
        positive = index_to_float(index)
        positive_is_nan = positive.nan?
        positive_finite = (!positive_is_nan)
        positive_ok = float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, positive)
        take_positive = (positive_finite && positive_ok)
        if take_positive
          found = positive
          return found
        end
        negative = f64_neg(positive)
        negative_is_nan = negative.nan?
        negative_finite = (!negative_is_nan)
        negative_ok = float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, negative)
        take_negative = (negative_finite && negative_ok)
        if take_negative
          found = negative
          return found
        end
        offset = ((offset + u1) & MASK)
      end
      simplest_bits = f2bits(simplest)
      min_is_nan = min_value.nan?
      min_finite = (!min_is_nan)
      min_bits = f2bits(min_value)
      min_distinct = (min_bits != simplest_bits)
      min_ok = float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, min_value)
      min_usable = (min_finite && min_distinct)
      take_min = (min_usable && min_ok)
      if take_min
        found = min_value
        return found
      end
      max_is_nan = max_value.nan?
      max_finite = (!max_is_nan)
      max_bits = f2bits(max_value)
      max_distinct = (max_bits != simplest_bits)
      max_ok = float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, max_value)
      max_usable = (max_finite && max_distinct)
      take_max = (max_usable && max_ok)
      if take_max
        found = max_value
        return found
      end
      mirrored = f64_neg(simplest)
      mirrored_is_nan = mirrored.nan?
      mirrored_finite = (!mirrored_is_nan)
      mirrored_bits = f2bits(mirrored)
      mirrored_distinct = (mirrored_bits != simplest_bits)
      mirrored_ok = float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, mirrored)
      mirrored_usable = (mirrored_finite && mirrored_distinct)
      take_mirrored = (mirrored_usable && mirrored_ok)
      if take_mirrored
        found = mirrored
        return found
      end
      found = simplest
      return found
    end

    def u64_to_bigint_le(value)
      out = String.new(encoding: Encoding::BINARY)
      i0 = 0
      i1 = 1
      i8 = 8
      u0 = 0
      u8 = 8
      u255 = 255
      shift = u0
      pos = i0
      loop do
        done = (pos >= i8)
        if done
          break
        end
        shifted = (value >> shift)
        byte_ = (shifted & u255)
        out << (byte_ & 0xff)
        shift = ((shift + u8) & MASK)
        pos = (pos + i1)
      end
      out << (u0 & 0xff)
      canonical = canonicalize_signed_le(out)
      return canonical
    end

    def bigint_to_u64_le(value)
      canonical = canonicalize_signed_le(value)
      i0 = 0
      i1 = 1
      i8 = 8
      i9 = 9
      u0 = 0
      u8 = 8
      u128 = 128
      length = canonical.bytesize
      last_pos = (length - i1)
      last = canonical.getbyte(last_pos)
      sign_bit = (last & u128)
      negative = (sign_bit != u0)
      if negative
        none = nil
        return none
      end
      too_wide = (length > i9)
      if too_wide
        none = nil
        return none
      end
      at_limit = (length == i9)
      if at_limit
        top = canonical.getbyte(i8)
        magnitude_in_top = (top != u0)
        if magnitude_in_top
          none = nil
          return none
        end
      end
      accumulator = u0
      shift = u0
      pos = i0
      loop do
        past_width = (pos >= i8)
        if past_width
          break
        end
        past_end = (pos >= length)
        if past_end
          break
        end
        byte_ = canonical.getbyte(pos)
        shifted = ((byte_ << shift) & MASK)
        accumulator = (accumulator | shifted)
        shift = ((shift + u8) & MASK)
        pos = (pos + i1)
      end
      found = accumulator
      return found
    end

    def max_finite_global_rank()
      max_finite_lex = 18442240474082181119
      lex = u64_to_bigint_le(max_finite_lex)
      two = bigint_two()
      one = bigint_one()
      doubled = signed_mul_le(lex, two)
      rank = signed_add_le(doubled, one)
      return rank
    end

    def float_global_rank(value)
      one = bigint_one()
      two = bigint_two()
      is_nan = value.nan?
      if is_nan
        mantissa_mask = 4503599627370495
        quiet_bit = 2251799813685248
        u63 = 63
        bits = f2bits(value)
        mantissa = (bits & mantissa_mask)
        nan_offset = (mantissa ^ quiet_bit)
        sign = (bits >> u63)
        base = max_finite_global_rank()
        three = signed_add_le(two, one)
        offset_big = u64_to_bigint_le(nan_offset)
        sign_big = u64_to_bigint_le(sign)
        spread = signed_mul_le(offset_big, two)
        with_base = signed_add_le(base, three)
        with_offset = signed_add_le(with_base, spread)
        rank = signed_add_le(with_offset, sign_big)
        return rank
      end
      is_infinite = !value.infinite?.nil?
      if is_infinite
        zero = 0.to_f
        base = max_finite_global_rank()
        positive = (value > zero)
        if positive
          rank = signed_add_le(base, one)
          return rank
        end
        rank = signed_add_le(base, two)
        return rank
      end
      negative = (f2bits(value) >> 63) == 1
      magnitude = f64_abs(value)
      lex = float_to_index(magnitude)
      lex_big = u64_to_bigint_le(lex)
      doubled = signed_mul_le(lex_big, two)
      sign_big = bigint_zero()
      if negative
        sign_big = bigint_one()
      end
      rank = signed_add_le(doubled, sign_big)
      return rank
    end

    def float_from_global_rank(rank)
      i0 = 0
      i1 = 1
      u0 = 0
      u1 = 1
      u52 = 52
      u56 = 56
      u63 = 63
      one = bigint_one()
      two = bigint_two()
      max_finite = max_finite_global_rank()
      ordering = signed_compare_le(rank, max_finite)
      beyond_finite = (ordering == i1)
      if beyond_finite
        offset = signed_sub_le(rank, max_finite)
        is_positive_infinity = signed_compare_le(offset, one)
        positive_infinity_slot = (is_positive_infinity == i0)
        if positive_infinity_slot
          infinity = f64_infinity()
          found = infinity
          return found
        end
        is_negative_infinity = signed_compare_le(offset, two)
        negative_infinity_slot = (is_negative_infinity == i0)
        if negative_infinity_slot
          negative_infinity = f64_neg_infinity()
          found = negative_infinity
          return found
        end
        three = signed_add_le(two, one)
        nan_relative = signed_sub_le(offset, three)
        sign_big = positive_rem_le_nonzero(nan_relative, two)
        mantissa_big = positive_div_le_nonzero(nan_relative, two)
        mantissa_opt = bigint_to_u64_le(mantissa_big)
        mantissa_fits = !mantissa_opt.nil?
        mantissa_too_wide = (!mantissa_fits)
        if mantissa_too_wide
          none = nil
          return none
        end
        mantissa_base = mantissa_opt
        overflow = (mantissa_base >> u52)
        overflows = (overflow != u0)
        if overflows
          none = nil
          return none
        end
        quiet_bit = 2251799813685248
        exponent_bits = 9218868437227405312
        mantissa = (mantissa_base ^ quiet_bit)
        sign_opt = bigint_to_u64_le(sign_big)
        sign = sign_opt
        sign_shifted = ((sign << u63) & MASK)
        with_exponent = (sign_shifted | exponent_bits)
        bits = (with_exponent | mantissa)
        candidate = bits2f(bits)
        candidate_is_nan = candidate.nan?
        if candidate_is_nan
          found = candidate
          return found
        end
        none = nil
        return none
      end
      negative_big = positive_rem_le_nonzero(rank, two)
      magnitude_big = positive_div_le_nonzero(rank, two)
      magnitude_opt = bigint_to_u64_le(magnitude_big)
      magnitude_fits = !magnitude_opt.nil?
      magnitude_too_wide = (!magnitude_fits)
      if magnitude_too_wide
        none = nil
        return none
      end
      lex = magnitude_opt
      simple_flag = (lex >> u63)
      simple = (simple_flag == u0)
      high_bits = (lex >> u56)
      too_large_for_simple = (high_bits != u0)
      unreachable_ = (simple && too_large_for_simple)
      if unreachable_
        none = nil
        return none
      end
      magnitude = index_to_float(lex)
      sign_opt = bigint_to_u64_le(negative_big)
      sign = sign_opt
      negative = (sign == u1)
      if negative
        mirrored = f64_neg(magnitude)
        found = mirrored
        return found
      end
      found = magnitude
      return found
    end

    def float_choice_max_index()
      nan_payloads = 9007199254740992
      base = max_finite_global_rank()
      two = bigint_two()
      payloads = u64_to_bigint_le(nan_payloads)
      with_infinities = signed_add_le(base, two)
      max_index = signed_add_le(with_infinities, payloads)
      return max_index
    end

    def float_choice_to_index(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, value)
      simplest_opt = float_simplest(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero)
      present = !simplest_opt.nil?
      absent = (!present)
      if absent
        none = nil
        return none
      end
      simplest = simplest_opt
      value_rank = float_global_rank(value)
      simplest_rank = float_global_rank(simplest)
      index = signed_sub_le(value_rank, simplest_rank)
      found = index.dup
      return found
    end

    def float_choice_from_index(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, index)
      simplest_opt = float_simplest(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero)
      present = !simplest_opt.nil?
      absent = (!present)
      if absent
        none = nil
        return none
      end
      simplest = simplest_opt
      simplest_rank = float_global_rank(simplest)
      raw = signed_add_le(simplest_rank, index)
      i0 = 0
      zero = bigint_zero()
      ordering = signed_compare_le(raw, zero)
      below_zero = (ordering < i0)
      if below_zero
        none = nil
        return none
      end
      candidate_opt = float_from_global_rank(raw)
      decoded = !candidate_opt.nil?
      undecodable = (!decoded)
      if undecodable
        none = nil
        return none
      end
      candidate = candidate_opt
      valid = float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, candidate)
      if valid
        found = candidate
        return found
      end
      none = nil
      return none
    end

    def code_length_counts(lengths, max_bits)
      i0 = 0
      i1 = 1
      i2 = 2
      u0 = 0
      u1 = 1
      u8 = 8
      u255 = 255
      counts = String.new(encoding: Encoding::BINARY)
      max_bits_i = u64_to_i64(max_bits)
      slots = (max_bits_i + i1)
      width = (slots * i2)
      fill = i0
      loop do
        filled = (fill >= width)
        if filled
          break
        end
        counts << (u0 & 0xff)
        fill = (fill + i1)
      end
      n = lengths.bytesize
      pos = i0
      loop do
        done = (pos >= n)
        if done
          break
        end
        length = lengths.getbyte(pos)
        unused = (length == u0)
        too_long = (length > max_bits)
        skip = (unused || too_long)
        countable = (!skip)
        if countable
          length_i = u64_to_i64(length)
          offset = (length_i * i2)
          high_offset = (offset + i1)
          low = counts.getbyte(offset)
          high = counts.getbyte(high_offset)
          shifted = ((high << u8) & MASK)
          current = (low | shifted)
          next_ = ((current + u1) & MASK)
          next_low = (next_ & u255)
          next_shifted = (next_ >> u8)
          next_high = (next_shifted & u255)
          counts.setbyte(offset, next_low & 0xff)
          counts.setbyte(high_offset, next_high & 0xff)
        end
        pos = (pos + i1)
      end
      return counts
    end

    def packed_u16_at(packed_, slot)
      i1 = 1
      i2 = 2
      u0 = 0
      u8 = 8
      n = packed_.bytesize
      slot_i = u64_to_i64(slot)
      offset = (slot_i * i2)
      high_offset = (offset + i1)
      past_end = (high_offset >= n)
      if past_end
        return u0
      end
      low = packed_.getbyte(offset)
      high = packed_.getbyte(high_offset)
      shifted = ((high << u8) & MASK)
      value = (low | shifted)
      return value
    end

    def code_length_count_at(counts, length)
      value = packed_u16_at(counts, length)
      return value
    end

    def code_lengths_valid(lengths, max_bits)
      u1 = 1
      true_ = true
      false_ = false
      counts = code_length_counts(lengths, max_bits)
      left = u1
      length = u1
      loop do
        done = (length > max_bits)
        if done
          break
        end
        doubled = ((left + left) & MASK)
        count = code_length_count_at(counts, length)
        over = (count > doubled)
        if over
          return false_
        end
        left = ((doubled - count) & MASK)
        length = ((length + u1) & MASK)
      end
      return true_
    end

    def read_bits(data, bit_pos, count)
      u0 = 0
      u1 = 1
      u3 = 3
      u7 = 7
      u8 = 8
      u64 = 64
      too_wide = (count > u64)
      if too_wide
        none = nil
        return none
      end
      n = data.bytesize
      n_u = (n & MASK)
      available = ((n_u * u8) & MASK)
      end_ = ((bit_pos + count) & MASK)
      past_end = (end_ > available)
      if past_end
        none = nil
        return none
      end
      value = u0
      taken = u0
      loop do
        done = (taken >= count)
        if done
          break
        end
        at = ((bit_pos + taken) & MASK)
        byte_index = (at >> u3)
        byte_offset = u64_to_i64(byte_index)
        byte_ = data.getbyte(byte_offset)
        bit_index = (at & u7)
        shifted = (byte_ >> bit_index)
        bit = (shifted & u1)
        placed = ((bit << taken) & MASK)
        value = (value | placed)
        taken = ((taken + u1) & MASK)
      end
      some = value
      return some
    end

    def symbol_offsets(counts, max_bits)
      i0 = 0
      i1 = 1
      i2 = 2
      u0 = 0
      u1 = 1
      u8 = 8
      u255 = 255
      offsets = String.new(encoding: Encoding::BINARY)
      max_bits_i = u64_to_i64(max_bits)
      slots = (max_bits_i + i2)
      width = (slots * i2)
      fill = i0
      loop do
        filled = (fill >= width)
        if filled
          break
        end
        offsets << (u0 & 0xff)
        fill = (fill + i1)
      end
      running = u0
      length = u1
      loop do
        done = (length > max_bits)
        if done
          break
        end
        length_i = u64_to_i64(length)
        offset = (length_i * i2)
        high_offset = (offset + i1)
        low = (running & u255)
        shifted = (running >> u8)
        high = (shifted & u255)
        offsets.setbyte(offset, low & 0xff)
        offsets.setbyte(high_offset, high & 0xff)
        count = code_length_count_at(counts, length)
        running = ((running + count) & MASK)
        length = ((length + u1) & MASK)
      end
      return offsets
    end

    def sorted_symbols(lengths, max_bits)
      i0 = 0
      i1 = 1
      i2 = 2
      u0 = 0
      u1 = 1
      u8 = 8
      u255 = 255
      counts = code_length_counts(lengths, max_bits)
      offsets = symbol_offsets(counts, max_bits)
      coded = u0
      length = u1
      loop do
        done = (length > max_bits)
        if done
          break
        end
        count = code_length_count_at(counts, length)
        coded = ((coded + count) & MASK)
        length = ((length + u1) & MASK)
      end
      symbols = String.new(encoding: Encoding::BINARY)
      coded_i = u64_to_i64(coded)
      width = (coded_i * i2)
      fill = i0
      loop do
        filled = (fill >= width)
        if filled
          break
        end
        symbols << (u0 & 0xff)
        fill = (fill + i1)
      end
      cursor = offsets.dup
      n = lengths.bytesize
      symbol = i0
      loop do
        done = (symbol >= n)
        if done
          break
        end
        length = lengths.getbyte(symbol)
        unused = (length == u0)
        too_long = (length > max_bits)
        skip = (unused || too_long)
        placeable = (!skip)
        if placeable
          slot = code_length_count_at(cursor, length)
          length_i = u64_to_i64(length)
          cursor_offset = (length_i * i2)
          cursor_high = (cursor_offset + i1)
          next_ = ((slot + u1) & MASK)
          next_low = (next_ & u255)
          next_shifted = (next_ >> u8)
          next_high = (next_shifted & u255)
          cursor.setbyte(cursor_offset, next_low & 0xff)
          cursor.setbyte(cursor_high, next_high & 0xff)
          slot_i = u64_to_i64(slot)
          slot_offset = (slot_i * i2)
          slot_high = (slot_offset + i1)
          symbol_u = (symbol & MASK)
          sym_low = (symbol_u & u255)
          sym_shifted = (symbol_u >> u8)
          sym_high = (sym_shifted & u255)
          symbols.setbyte(slot_offset, sym_low & 0xff)
          symbols.setbyte(slot_high, sym_high & 0xff)
        end
        symbol = (symbol + i1)
      end
      return symbols
    end

    def huffman_decode(data, bit_pos, counts, symbols, max_bits)
      u0 = 0
      u1 = 1
      u32 = 32
      code = u0
      first = u0
      index = u0
      length = u1
      loop do
        done = (length > max_bits)
        if done
          break
        end
        at = ((length - u1) & MASK)
        bit_at = ((bit_pos + at) & MASK)
        bit = read_bits(data, bit_at, u1)
        have_bit = !bit.nil?
        truncated = (!have_bit)
        if truncated
          none = nil
          return none
        end
        bit_value = bit
        code = (code | bit_value)
        count = code_length_count_at(counts, length)
        span = ((first + count) & MASK)
        within = (code < span)
        if within
          rank = ((code - first) & MASK)
          slot = ((index + rank) & MASK)
          symbol = packed_u16_at(symbols, slot)
          shifted_len = ((length << u32) & MASK)
          packed_ = (shifted_len | symbol)
          some = packed_
          return some
        end
        index = ((index + count) & MASK)
        first = ((span + span) & MASK)
        code = ((code + code) & MASK)
        length = ((length + u1) & MASK)
      end
      none = nil
      return none
    end

    def length_base(symbol)
      u0 = 0
      u2 = 2
      u3 = 3
      u4 = 4
      u254 = 254
      u257 = 257
      u261 = 261
      u264 = 264
      u265 = 265
      u285 = 285
      u258 = 258
      below = (symbol < u257)
      above = (symbol > u285)
      outside = (below || above)
      if outside
        return u0
      end
      is_max = (symbol == u285)
      if is_max
        return u258
      end
      flat = (symbol <= u264)
      if flat
        base = ((symbol - u254) & MASK)
        return base
      end
      extra_index = ((symbol - u261) & MASK)
      extra = (extra_index >> u2)
      step = ((symbol - u265) & MASK)
      within = (step & u3)
      mantissa = ((within + u4) & MASK)
      scaled = ((mantissa << extra) & MASK)
      base = ((scaled + u3) & MASK)
      return base
    end

    def length_extra(symbol)
      u0 = 0
      u2 = 2
      u257 = 257
      u261 = 261
      u264 = 264
      u285 = 285
      below = (symbol < u257)
      above = (symbol > u285)
      outside = (below || above)
      if outside
        return u0
      end
      is_max = (symbol == u285)
      if is_max
        return u0
      end
      flat = (symbol <= u264)
      if flat
        return u0
      end
      extra_index = ((symbol - u261) & MASK)
      extra = (extra_index >> u2)
      return extra
    end

    def distance_base(symbol)
      u0 = 0
      u1 = 1
      u2 = 2
      u3 = 3
      u29 = 29
      above = (symbol > u29)
      if above
        return u0
      end
      flat = (symbol <= u3)
      if flat
        base = ((symbol + u1) & MASK)
        return base
      end
      extra_index = ((symbol - u2) & MASK)
      extra = (extra_index >> u1)
      parity = (symbol & u1)
      mantissa = ((parity + u2) & MASK)
      scaled = ((mantissa << extra) & MASK)
      base = ((scaled + u1) & MASK)
      return base
    end

    def distance_extra(symbol)
      u0 = 0
      u1 = 1
      u2 = 2
      u3 = 3
      u29 = 29
      above = (symbol > u29)
      if above
        return u0
      end
      flat = (symbol <= u3)
      if flat
        return u0
      end
      extra_index = ((symbol - u2) & MASK)
      extra = (extra_index >> u1)
      return extra
    end

    def fixed_literal_lengths()
      i0 = 0
      i1 = 1
      i288 = 288
      i144 = 144
      i256 = 256
      i280 = 280
      u7 = 7
      u8 = 8
      u9 = 9
      lengths = String.new(encoding: Encoding::BINARY)
      symbol = i0
      loop do
        done = (symbol >= i288)
        if done
          break
        end
        length = u8
        past_144 = (symbol >= i144)
        below_256 = (symbol < i256)
        is_nine = (past_144 && below_256)
        if is_nine
          length = u9
        end
        past_256 = (symbol >= i256)
        below_280 = (symbol < i280)
        is_seven = (past_256 && below_280)
        if is_seven
          length = u7
        end
        lengths << (length & 0xff)
        symbol = (symbol + i1)
      end
      return lengths
    end

    def fixed_distance_lengths()
      i0 = 0
      i1 = 1
      i30 = 30
      u5 = 5
      lengths = String.new(encoding: Encoding::BINARY)
      symbol = i0
      loop do
        done = (symbol >= i30)
        if done
          break
        end
        lengths << (u5 & 0xff)
        symbol = (symbol + i1)
      end
      return lengths
    end

    def code_length_order()
      order = String.new(encoding: Encoding::BINARY)
      u0 = 0
      u1 = 1
      u2 = 2
      u3 = 3
      u4 = 4
      u5 = 5
      u6 = 6
      u7 = 7
      u8 = 8
      u9 = 9
      u10 = 10
      u11 = 11
      u12 = 12
      u13 = 13
      u14 = 14
      u15 = 15
      u16 = 16
      u17 = 17
      u18 = 18
      order << (u16 & 0xff)
      order << (u17 & 0xff)
      order << (u18 & 0xff)
      order << (u0 & 0xff)
      order << (u8 & 0xff)
      order << (u7 & 0xff)
      order << (u9 & 0xff)
      order << (u6 & 0xff)
      order << (u10 & 0xff)
      order << (u5 & 0xff)
      order << (u11 & 0xff)
      order << (u4 & 0xff)
      order << (u12 & 0xff)
      order << (u3 & 0xff)
      order << (u13 & 0xff)
      order << (u2 & 0xff)
      order << (u14 & 0xff)
      order << (u1 & 0xff)
      order << (u15 & 0xff)
      return order
    end

    def max_decompressed_len()
      max = 16777216
      return max
    end

    def inflate(data)
      limit = max_decompressed_len()
      out = inflate_bounded(data, limit)
      return out
    end

    def inflate_bounded(data, limit)
      i0 = 0
      u0 = 0
      u1 = 1
      u2 = 2
      u3 = 3
      u4 = 4
      u5 = 5
      u7 = 7
      u8 = 8
      u15 = 15
      u16 = 16
      u17 = 17
      u19 = 19
      u32 = 32
      u65535 = 65535
      u256 = 256
      u257 = 257
      u285 = 285
      u286 = 286
      u29 = 29
      u30 = 30
      u11 = 11
      out = String.new(encoding: Encoding::BINARY)
      bit_pos = u0
      order = code_length_order()
      loop do
        final_opt = read_bits(data, bit_pos, u1)
        have_final = !final_opt.nil?
        no_final = (!have_final)
        if no_final
          none = nil
          return none
        end
        final_ = final_opt
        bit_pos = ((bit_pos + u1) & MASK)
        type_opt = read_bits(data, bit_pos, u2)
        have_type = !type_opt.nil?
        no_type = (!have_type)
        if no_type
          none = nil
          return none
        end
        block_type = type_opt
        bit_pos = ((bit_pos + u2) & MASK)
        reserved = (block_type == u3)
        if reserved
          none = nil
          return none
        end
        stored = (block_type == u0)
        if stored
          slack = (bit_pos & u7)
          needs_pad = (slack > u0)
          if needs_pad
            pad = ((u8 - slack) & MASK)
            bit_pos = ((bit_pos + pad) & MASK)
          end
          len_opt = read_bits(data, bit_pos, u16)
          have_len = !len_opt.nil?
          no_len = (!have_len)
          if no_len
            none = nil
            return none
          end
          len_ = len_opt
          bit_pos = ((bit_pos + u16) & MASK)
          nlen_opt = read_bits(data, bit_pos, u16)
          have_nlen = !nlen_opt.nil?
          no_nlen = (!have_nlen)
          if no_nlen
            none = nil
            return none
          end
          nlen = nlen_opt
          bit_pos = ((bit_pos + u16) & MASK)
          complement = (len_ ^ u65535)
          agrees = (nlen == complement)
          disagrees = (!agrees)
          if disagrees
            none = nil
            return none
          end
          stored_produced = out.bytesize
          stored_produced_u = (stored_produced & MASK)
          stored_total = ((stored_produced_u + len_) & MASK)
          stored_over = (stored_total > limit)
          if stored_over
            none = nil
            return none
          end
          copied = u0
          loop do
            copy_done = (copied >= len_)
            if copy_done
              break
            end
            byte_opt = read_bits(data, bit_pos, u8)
            have_byte = !byte_opt.nil?
            no_byte = (!have_byte)
            if no_byte
              none = nil
              return none
            end
            byte_ = byte_opt
            out << (byte_ & 0xff)
            bit_pos = ((bit_pos + u8) & MASK)
            copied = ((copied + u1) & MASK)
          end
        end
        compressed = (!stored)
        if compressed
          lit_lengths = fixed_literal_lengths()
          dist_lengths = fixed_distance_lengths()
          dynamic = (block_type == u2)
          if dynamic
            hlit_opt = read_bits(data, bit_pos, u5)
            have_hlit = !hlit_opt.nil?
            no_hlit = (!have_hlit)
            if no_hlit
              none = nil
              return none
            end
            hlit_raw = hlit_opt
            hlit = ((hlit_raw + u257) & MASK)
            bit_pos = ((bit_pos + u5) & MASK)
            hdist_opt = read_bits(data, bit_pos, u5)
            have_hdist = !hdist_opt.nil?
            no_hdist = (!have_hdist)
            if no_hdist
              none = nil
              return none
            end
            hdist_raw = hdist_opt
            hdist = ((hdist_raw + u1) & MASK)
            bit_pos = ((bit_pos + u5) & MASK)
            hclen_opt = read_bits(data, bit_pos, u4)
            have_hclen = !hclen_opt.nil?
            no_hclen = (!have_hclen)
            if no_hclen
              none = nil
              return none
            end
            hclen_raw = hclen_opt
            hclen = ((hclen_raw + u4) & MASK)
            bit_pos = ((bit_pos + u4) & MASK)
            hlit_bad = (hlit > u286)
            hdist_bad = (hdist > u30)
            header_bad = (hlit_bad || hdist_bad)
            if header_bad
              none = nil
              return none
            end
            cl_lengths = String.new(encoding: Encoding::BINARY)
            zero_fill = u0
            loop do
              zeroed = (zero_fill >= u19)
              if zeroed
                break
              end
              cl_lengths << (u0 & 0xff)
              zero_fill = ((zero_fill + u1) & MASK)
            end
            cl_read = u0
            loop do
              cl_done = (cl_read >= hclen)
              if cl_done
                break
              end
              cl_opt = read_bits(data, bit_pos, u3)
              have_cl = !cl_opt.nil?
              no_cl = (!have_cl)
              if no_cl
                none = nil
                return none
              end
              cl_value = cl_opt
              bit_pos = ((bit_pos + u3) & MASK)
              order_index = u64_to_i64(cl_read)
              slot = order.getbyte(order_index)
              cl_lengths.setbyte(slot, cl_value & 0xff)
              cl_read = ((cl_read + u1) & MASK)
            end
            cl_ok = code_lengths_valid(cl_lengths, u7)
            cl_bad = (!cl_ok)
            if cl_bad
              none = nil
              return none
            end
            cl_counts = code_length_counts(cl_lengths, u7)
            cl_symbols = sorted_symbols(cl_lengths, u7)
            wanted = ((hlit + hdist) & MASK)
            all_lengths = String.new(encoding: Encoding::BINARY)
            have = u0
            previous = u0
            loop do
              enough = (have >= wanted)
              if enough
                break
              end
              decoded = huffman_decode(data, bit_pos, cl_counts, cl_symbols, u7)
              have_decoded = !decoded.nil?
              no_decoded = (!have_decoded)
              if no_decoded
                none = nil
                return none
              end
              packed_ = decoded
              used = (packed_ >> u32)
              symbol = (packed_ & u65535)
              bit_pos = ((bit_pos + used) & MASK)
              literal = (symbol < u16)
              if literal
                all_lengths << (symbol & 0xff)
                previous = symbol
                have = ((have + u1) & MASK)
              end
              repeats = (!literal)
              if repeats
                repeat_previous = (symbol == u16)
                extra_width = u7
                run_base = u11
                value = u0
                if repeat_previous
                  extra_width = u2
                  run_base = u3
                  value = previous
                  nothing_yet = (have == u0)
                  if nothing_yet
                    none = nil
                    return none
                  end
                end
                short_zeroes = (symbol == u17)
                if short_zeroes
                  extra_width = u3
                  run_base = u3
                end
                extra_opt = read_bits(data, bit_pos, extra_width)
                have_extra = !extra_opt.nil?
                no_extra = (!have_extra)
                if no_extra
                  none = nil
                  return none
                end
                extra = extra_opt
                bit_pos = ((bit_pos + extra_width) & MASK)
                run = ((run_base + extra) & MASK)
                over = ((have + run) & MASK)
                overruns = (over > wanted)
                if overruns
                  none = nil
                  return none
                end
                written = u0
                loop do
                  run_done = (written >= run)
                  if run_done
                    break
                  end
                  all_lengths << (value & 0xff)
                  written = ((written + u1) & MASK)
                end
                have = ((have + run) & MASK)
              end
            end
            hlit_i = u64_to_i64(hlit)
            wanted_i = u64_to_i64(wanted)
            lit_lengths = all_lengths.byteslice(i0, hlit_i - i0).dup
            dist_lengths = all_lengths.byteslice(hlit_i, wanted_i - hlit_i).dup
          end
          lit_ok = code_lengths_valid(lit_lengths, u15)
          dist_ok = code_lengths_valid(dist_lengths, u15)
          codes_ok = (lit_ok && dist_ok)
          codes_bad = (!codes_ok)
          if codes_bad
            none = nil
            return none
          end
          lit_counts = code_length_counts(lit_lengths, u15)
          lit_symbols = sorted_symbols(lit_lengths, u15)
          dist_counts = code_length_counts(dist_lengths, u15)
          dist_symbols = sorted_symbols(dist_lengths, u15)
          loop do
            decoded = huffman_decode(data, bit_pos, lit_counts, lit_symbols, u15)
            have_decoded = !decoded.nil?
            no_decoded = (!have_decoded)
            if no_decoded
              none = nil
              return none
            end
            packed_ = decoded
            used = (packed_ >> u32)
            symbol = (packed_ & u65535)
            bit_pos = ((bit_pos + used) & MASK)
            end_of_block = (symbol == u256)
            if end_of_block
              break
            end
            is_literal = (symbol < u256)
            if is_literal
              literal_produced = out.bytesize
              literal_produced_u = (literal_produced & MASK)
              literal_full = (literal_produced_u >= limit)
              if literal_full
                none = nil
                return none
              end
              out << (symbol & 0xff)
            end
            is_match = (symbol > u256)
            if is_match
              unknown = (symbol > u285)
              if unknown
                none = nil
                return none
              end
              base = length_base(symbol)
              width = length_extra(symbol)
              len_extra_opt = read_bits(data, bit_pos, width)
              have_len_extra = !len_extra_opt.nil?
              no_len_extra = (!have_len_extra)
              if no_len_extra
                none = nil
                return none
              end
              len_extra = len_extra_opt
              bit_pos = ((bit_pos + width) & MASK)
              match_length = ((base + len_extra) & MASK)
              dist_decoded = huffman_decode(data, bit_pos, dist_counts, dist_symbols, u15)
              have_dist = !dist_decoded.nil?
              no_dist = (!have_dist)
              if no_dist
                none = nil
                return none
              end
              dist_packed = dist_decoded
              dist_used = (dist_packed >> u32)
              dist_symbol = (dist_packed & u65535)
              bit_pos = ((bit_pos + dist_used) & MASK)
              dist_unknown = (dist_symbol > u29)
              if dist_unknown
                none = nil
                return none
              end
              dist_base = distance_base(dist_symbol)
              dist_width = distance_extra(dist_symbol)
              dist_extra_opt = read_bits(data, bit_pos, dist_width)
              have_dist_extra = !dist_extra_opt.nil?
              no_dist_extra = (!have_dist_extra)
              if no_dist_extra
                none = nil
                return none
              end
              dist_extra = dist_extra_opt
              bit_pos = ((bit_pos + dist_width) & MASK)
              distance = ((dist_base + dist_extra) & MASK)
              produced = out.bytesize
              produced_u = (produced & MASK)
              too_far = (distance > produced_u)
              if too_far
                none = nil
                return none
              end
              match_total = ((produced_u + match_length) & MASK)
              match_over = (match_total > limit)
              if match_over
                none = nil
                return none
              end
              from_ = ((produced_u - distance) & MASK)
              taken = u0
              loop do
                match_done = (taken >= match_length)
                if match_done
                  break
                end
                at = ((from_ + taken) & MASK)
                at_i = u64_to_i64(at)
                byte_ = out.getbyte(at_i)
                out << (byte_ & 0xff)
                taken = ((taken + u1) & MASK)
              end
            end
          end
        end
        last = (final_ > u0)
        if last
          break
        end
      end
      some = out.dup
      return some
    end

    def adler32(data)
      i0 = 0
      i1 = 1
      u0 = 0
      u1 = 1
      u16 = 16
      u65521 = 65521
      low = u1
      high = u0
      n = data.bytesize
      pos = i0
      loop do
        done = (pos >= n)
        if done
          break
        end
        byte_ = data.getbyte(pos)
        low_sum = ((low + byte_) & MASK)
        low = low_sum
        low_over = (low_sum >= u65521)
        if low_over
          low = ((low_sum - u65521) & MASK)
        end
        high_sum = ((high + low) & MASK)
        high = high_sum
        high_over = (high_sum >= u65521)
        if high_over
          high = ((high_sum - u65521) & MASK)
        end
        pos = (pos + i1)
      end
      shifted = ((high << u16) & MASK)
      value = (shifted | low)
      return value
    end

    def zlib_decompress(data)
      limit = max_decompressed_len()
      out = zlib_decompress_bounded(data, limit)
      return out
    end

    def zlib_decompress_bounded(data, limit)
      i0 = 0
      i1 = 1
      i2 = 2
      i4 = 4
      i6 = 6
      u0 = 0
      u8 = 8
      u15 = 15
      u31 = 31
      u32 = 32
      u256 = 256
      n = data.bytesize
      too_short = (n < i6)
      if too_short
        none = nil
        return none
      end
      cmf = data.getbyte(i0)
      flg = data.getbyte(i1)
      method = (cmf & u15)
      not_deflate = (method != u8)
      if not_deflate
        none = nil
        return none
      end
      scaled = ((cmf * u256) & MASK)
      header = ((scaled + flg) & MASK)
      check = header
      loop do
        reduced = (check < u31)
        if reduced
          break
        end
        check = ((check - u31) & MASK)
      end
      bad_check = (check != u0)
      if bad_check
        none = nil
        return none
      end
      u32_flag = (flg & u32)
      has_dict = (u32_flag > u0)
      if has_dict
        none = nil
        return none
      end
      body_end = (n - i4)
      body = data.byteslice(i2, body_end - i2).dup
      inflated = inflate_bounded(body, limit)
      present = !inflated.nil?
      missing = (!present)
      if missing
        none = nil
        return none
      end
      out = inflated
      expected = u0
      at = body_end
      loop do
        read_done = (at >= n)
        if read_done
          break
        end
        byte_ = data.getbyte(at)
        moved = ((expected * u256) & MASK)
        expected = ((moved + byte_) & MASK)
        at = (at + i1)
      end
      actual = adler32(out)
      agrees = (actual == expected)
      disagrees = (!agrees)
      if disagrees
        none = nil
        return none
      end
      some = out.dup
      return some
    end

    def deflate_write_bits(state, value, count)
      i0 = 0
      i1 = 1
      u0 = 0
      u1 = 1
      u8 = 8
      u255 = 255
      out = String.new(encoding: Encoding::BINARY)
      n = state.bytesize
      copy_pos = i0
      loop do
        copy_done = (copy_pos >= n)
        if copy_done
          break
        end
        copy_byte = state.getbyte(copy_pos)
        out << (copy_byte & 0xff)
        copy_pos = (copy_pos + i1)
      end
      remaining = value
      written = u0
      loop do
        done = (written >= count)
        if done
          break
        end
        used = out.getbyte(i0)
        at_boundary = (used == u0)
        if at_boundary
          out << (u0 & 0xff)
        end
        out_n = out.bytesize
        last = (out_n - i1)
        current = out.getbyte(last)
        bit = (remaining & u1)
        shifted = ((bit << used) & MASK)
        next_ = (current | shifted)
        next_byte = (next_ & u255)
        out.setbyte(last, next_byte & 0xff)
        next_used_raw = ((used + u1) & MASK)
        next_used = next_used_raw
        full = (next_used_raw == u8)
        if full
          next_used = u0
        end
        out.setbyte(i0, next_used & 0xff)
        remaining = (remaining >> u1)
        written = ((written + u1) & MASK)
      end
      return out
    end

    def deflate_drain_complete(state)
      i0 = 0
      i1 = 1
      u0 = 0
      used = state.getbyte(i0)
      n = state.bytesize
      end_ = n
      partial = (used != u0)
      if partial
        end_ = (n - i1)
      end
      out = state.byteslice(i1, end_ - i1).dup
      return out
    end

    def deflate_drain_carry(state)
      i0 = 0
      i1 = 1
      u0 = 0
      out = String.new(encoding: Encoding::BINARY)
      used = state.getbyte(i0)
      out << (used & 0xff)
      partial = (used != u0)
      if partial
        n = state.bytesize
        last = (n - i1)
        last_byte = state.getbyte(last)
        out << (last_byte & 0xff)
      end
      return out
    end

    def deflate_reverse_code(code, width)
      u64 = 64
      reversed = rev64(code)
      shift = ((u64 - width) & MASK)
      out = (reversed >> shift)
      return out
    end

    def deflate_fixed_symbol(state, symbol)
      u0 = 0
      u7 = 7
      u8 = 8
      u9 = 9
      u48 = 48
      u143 = 143
      u144 = 144
      u255 = 255
      u256 = 256
      u279 = 279
      u280 = 280
      u400 = 400
      u192 = 192
      code = u0
      code_width = u8
      first = (symbol <= u143)
      if first
        code = ((u48 + symbol) & MASK)
      end
      second_low = (symbol >= u144)
      second_high = (symbol <= u255)
      second = (second_low && second_high)
      if second
        code = ((u400 + symbol) & MASK)
        code = ((code - u144) & MASK)
        code_width = u9
      end
      third_low = (symbol >= u256)
      third_high = (symbol <= u279)
      third = (third_low && third_high)
      if third
        code = ((symbol - u256) & MASK)
        code_width = u7
      end
      fourth = (symbol >= u280)
      if fourth
        offset = ((symbol - u280) & MASK)
        code = ((u192 + offset) & MASK)
        code_width = u8
      end
      wire_code = deflate_reverse_code(code, code_width)
      out = deflate_write_bits(state, wire_code, code_width)
      return out
    end

    def deflate_hash(b0, b1, b2)
      u8 = 8
      u16 = 16
      u17 = 17
      u2654435761 = 2654435761
      u4294967295 = 4294967295
      b0s = ((b0 << u16) & MASK)
      b1s = ((b1 << u8) & MASK)
      partial = (b0s | b1s)
      key = (partial | b2)
      mixed = ((key * u2654435761) & MASK)
      mixed32 = (mixed & u4294967295)
      bucket = (mixed32 >> u17)
      return bucket
    end

    def deflate_token_entry(tag, value, distance)
      u8 = 8
      u255 = 255
      value_u = (value & MASK)
      distance_u = (distance & MASK)
      value_low = (value_u & u255)
      value_shifted = (value_u >> u8)
      value_high = (value_shifted & u255)
      distance_low = (distance_u & u255)
      distance_shifted = (distance_u >> u8)
      distance_high = (distance_shifted & u255)
      entry = String.new(encoding: Encoding::BINARY)
      entry << (tag & 0xff)
      entry << (value_low & 0xff)
      entry << (value_high & 0xff)
      entry << (distance_low & 0xff)
      entry << (distance_high & 0xff)
      return entry
    end

    def deflate_tokens(data)
      i0 = 0
      i1 = 1
      i2 = 2
      i3 = 3
      i5 = 5
      i128 = 128
      i258 = 258
      i32768 = 32768
      u0 = 0
      u1 = 1
      u4 = 4
      u8 = 8
      u16 = 16
      u24 = 24
      u255 = 255
      u32767 = 32767
      u131072 = 131072
      tokens = String.new(encoding: Encoding::BINARY)
      n = data.bytesize
      head = ("\0".b * u131072)
      prev = ("\0".b * u131072)
      hashed = i1
      pos = i0
      saved_length = i0
      saved_distance = i0
      loop do
        done = (pos >= n)
        if done
          break
        end
        loop do
          caught_up = (hashed >= pos)
          if caught_up
            break
          end
          hash_end = (hashed + i2)
          hashable = (hash_end < n)
          if hashable
            hb0 = data.getbyte(hashed)
            hb1_at = (hashed + i1)
            hb1 = data.getbyte(hb1_at)
            hb2 = data.getbyte(hash_end)
            bucket = deflate_hash(hb0, hb1, hb2)
            head_off_u = ((bucket * u4) & MASK)
            head_off = u64_to_i64(head_off_u)
            head_off1 = (head_off + i1)
            head_off2 = (head_off + i2)
            head_off3 = (head_off + i3)
            old0 = head.getbyte(head_off)
            old1 = head.getbyte(head_off1)
            old2 = head.getbyte(head_off2)
            old3 = head.getbyte(head_off3)
            p_u = (hashed & MASK)
            p_slot = (p_u & u32767)
            prev_off_u = ((p_slot * u4) & MASK)
            prev_off = u64_to_i64(prev_off_u)
            prev_off1 = (prev_off + i1)
            prev_off2 = (prev_off + i2)
            prev_off3 = (prev_off + i3)
            prev.setbyte(prev_off, old0 & 0xff)
            prev.setbyte(prev_off1, old1 & 0xff)
            prev.setbyte(prev_off2, old2 & 0xff)
            prev.setbyte(prev_off3, old3 & 0xff)
            p_b0 = (p_u & u255)
            p_s1 = (p_u >> u8)
            p_b1 = (p_s1 & u255)
            p_s2 = (p_u >> u16)
            p_b2 = (p_s2 & u255)
            p_s3 = (p_u >> u24)
            p_b3 = (p_s3 & u255)
            head.setbyte(head_off, p_b0 & 0xff)
            head.setbyte(head_off1, p_b1 & 0xff)
            head.setbyte(head_off2, p_b2 & 0xff)
            head.setbyte(head_off3, p_b3 & 0xff)
          end
          hashed = (hashed + i1)
        end
        has_saved = (saved_length > i0)
        threshold = i2
        if has_saved
          threshold = saved_length
        end
        best_length = threshold
        best_distance = i0
        probes_left = i128
        tail2 = (pos + i2)
        searchable = (tail2 < n)
        if searchable
          window_start = (pos - i32768)
          before_start = (window_start < i1)
          if before_start
            window_start = i1
          end
          sb0 = data.getbyte(pos)
          sb1_at = (pos + i1)
          sb1 = data.getbyte(sb1_at)
          sb2 = data.getbyte(tail2)
          search_bucket = deflate_hash(sb0, sb1, sb2)
          sh_off_u = ((search_bucket * u4) & MASK)
          sh_off = u64_to_i64(sh_off_u)
          sh_off1 = (sh_off + i1)
          sh_off2 = (sh_off + i2)
          sh_off3 = (sh_off + i3)
          c0 = head.getbyte(sh_off)
          c1 = head.getbyte(sh_off1)
          c2 = head.getbyte(sh_off2)
          c3 = head.getbyte(sh_off3)
          c1s = ((c1 << u8) & MASK)
          c2s = ((c2 << u16) & MASK)
          c3s = ((c3 << u24) & MASK)
          c01 = (c0 | c1s)
          c012 = (c01 | c2s)
          candidate_u = (c012 | c3s)
          candidate = u64_to_i64(candidate_u)
          loop do
            in_window = (candidate >= window_start)
            out_of_window = (!in_window)
            if out_of_window
              break
            end
            distance = (pos - candidate)
            matched = i0
            loop do
              at_limit = (matched >= i258)
              if at_limit
                break
              end
              target_at = (pos + matched)
              past_input = (target_at >= n)
              if past_input
                break
              end
              source_offset = matched
              loop do
                offset_small = (source_offset < distance)
                if offset_small
                  break
                end
                source_offset = (source_offset - distance)
              end
              source_at = (candidate + source_offset)
              source_byte = data.getbyte(source_at)
              target_byte = data.getbyte(target_at)
              different = (source_byte != target_byte)
              if different
                break
              end
              matched = (matched + i1)
            end
            better = (matched > best_length)
            if better
              best_length = matched
              best_distance = distance
            end
            maximal = (best_length == i258)
            if maximal
              break
            end
            probes_left = (probes_left - i1)
            exhausted = (probes_left <= i0)
            if exhausted
              break
            end
            c_u = (candidate & MASK)
            c_slot = (c_u & u32767)
            pv_off_u = ((c_slot * u4) & MASK)
            pv_off = u64_to_i64(pv_off_u)
            pv_off1 = (pv_off + i1)
            pv_off2 = (pv_off + i2)
            pv_off3 = (pv_off + i3)
            pv0 = prev.getbyte(pv_off)
            pv1 = prev.getbyte(pv_off1)
            pv2 = prev.getbyte(pv_off2)
            pv3 = prev.getbyte(pv_off3)
            pv1s = ((pv1 << u8) & MASK)
            pv2s = ((pv2 << u16) & MASK)
            pv3s = ((pv3 << u24) & MASK)
            pv01 = (pv0 | pv1s)
            pv012 = (pv01 | pv2s)
            next_u = (pv012 | pv3s)
            candidate = u64_to_i64(next_u)
          end
        end
        found = (best_distance > i0)
        current_length = i0
        current_distance = i0
        if found
          current_length = best_length
          current_distance = best_distance
        end
        if has_saved
          later_better = (current_length > saved_length)
          if later_better
            literal_at = (pos - i1)
            literal_u = data.getbyte(literal_at)
            literal = u64_to_i64(literal_u)
            entry = deflate_token_entry(u0, literal, i0)
            entry_at = i0
            loop do
              entry_done = (entry_at >= i5)
              if entry_done
                break
              end
              entry_byte = entry.getbyte(entry_at)
              tokens << (entry_byte & 0xff)
              entry_at = (entry_at + i1)
            end
            long_ = (current_length >= i128)
            if long_
              entry = deflate_token_entry(u1, current_length, current_distance)
              entry_at = i0
              loop do
                entry_done = (entry_at >= i5)
                if entry_done
                  break
                end
                entry_byte = entry.getbyte(entry_at)
                tokens << (entry_byte & 0xff)
                entry_at = (entry_at + i1)
              end
              pos = (pos + current_length)
              saved_length = i0
              saved_distance = i0
            end
            short_ = (!long_)
            if short_
              saved_length = current_length
              saved_distance = current_distance
              pos = (pos + i1)
            end
          end
          keep_saved = (!later_better)
          if keep_saved
            entry = deflate_token_entry(u1, saved_length, saved_distance)
            entry_at = i0
            loop do
              entry_done = (entry_at >= i5)
              if entry_done
                break
              end
              entry_byte = entry.getbyte(entry_at)
              tokens << (entry_byte & 0xff)
              entry_at = (entry_at + i1)
            end
            remaining = (saved_length - i1)
            pos = (pos + remaining)
            saved_length = i0
            saved_distance = i0
          end
        end
        no_saved = (!has_saved)
        if no_saved
          has_match = (current_length >= i3)
          if has_match
            long_ = (current_length >= i128)
            if long_
              entry = deflate_token_entry(u1, current_length, current_distance)
              entry_at = i0
              loop do
                entry_done = (entry_at >= i5)
                if entry_done
                  break
                end
                entry_byte = entry.getbyte(entry_at)
                tokens << (entry_byte & 0xff)
                entry_at = (entry_at + i1)
              end
              pos = (pos + current_length)
            end
            short_ = (!long_)
            if short_
              saved_length = current_length
              saved_distance = current_distance
              pos = (pos + i1)
            end
          end
          no_match = (!has_match)
          if no_match
            literal_u = data.getbyte(pos)
            literal = u64_to_i64(literal_u)
            entry = deflate_token_entry(u0, literal, i0)
            entry_at = i0
            loop do
              entry_done = (entry_at >= i5)
              if entry_done
                break
              end
              entry_byte = entry.getbyte(entry_at)
              tokens << (entry_byte & 0xff)
              entry_at = (entry_at + i1)
            end
            pos = (pos + i1)
          end
        end
      end
      pending = (saved_length > i0)
      if pending
        entry = deflate_token_entry(u1, saved_length, saved_distance)
        entry_at = i0
        loop do
          entry_done = (entry_at >= i5)
          if entry_done
            break
          end
          entry_byte = entry.getbyte(entry_at)
          tokens << (entry_byte & 0xff)
          entry_at = (entry_at + i1)
        end
      end
      return tokens
    end

    def deflate_fixed(data)
      i0 = 0
      i1 = 1
      i2 = 2
      i3 = 3
      i4 = 4
      i5 = 5
      u0 = 0
      u1 = 1
      u3 = 3
      u5 = 5
      u8 = 8
      u256 = 256
      u257 = 257
      u258 = 258
      u285 = 285
      u30 = 30
      out = String.new(encoding: Encoding::BINARY)
      state = String.new(encoding: Encoding::BINARY)
      state << (u0 & 0xff)
      state = deflate_write_bits(state, u3, u3)
      tokens = deflate_tokens(data)
      n = tokens.bytesize
      pos = i0
      loop do
        done = (pos >= n)
        if done
          break
        end
        tag = tokens.getbyte(pos)
        is_match = (tag == u1)
        if is_match
          value_low_at = (pos + i1)
          value_high_at = (pos + i2)
          distance_low_at = (pos + i3)
          distance_high_at = (pos + i4)
          value_low = tokens.getbyte(value_low_at)
          value_high = tokens.getbyte(value_high_at)
          value_high_shifted = ((value_high << u8) & MASK)
          length_u = (value_low | value_high_shifted)
          distance_low = tokens.getbyte(distance_low_at)
          distance_high = tokens.getbyte(distance_high_at)
          distance_high_shifted = ((distance_high << u8) & MASK)
          distance_u = (distance_low | distance_high_shifted)
          length_symbol = u257
          loop do
            last_length = (length_symbol >= u285)
            if last_length
              break
            end
            base = length_base(length_symbol)
            extra_count = length_extra(length_symbol)
            span = ((u1 << extra_count) & MASK)
            upper = ((base + span) & MASK)
            fits = (length_u < upper)
            if fits
              break
            end
            length_symbol = ((length_symbol + u1) & MASK)
          end
          maximum_length = (length_u == u258)
          if maximum_length
            length_symbol = u285
          end
          state = deflate_fixed_symbol(state, length_symbol)
          length_base_value = length_base(length_symbol)
          length_extra_count = length_extra(length_symbol)
          length_extra_value = ((length_u - length_base_value) & MASK)
          state = deflate_write_bits(state, length_extra_value, length_extra_count)
          distance_symbol = u0
          loop do
            last_distance = (distance_symbol >= u30)
            if last_distance
              break
            end
            distance_base_value = distance_base(distance_symbol)
            distance_extra_count = distance_extra(distance_symbol)
            distance_span = ((u1 << distance_extra_count) & MASK)
            distance_upper = ((distance_base_value + distance_span) & MASK)
            distance_fits = (distance_u < distance_upper)
            if distance_fits
              break
            end
            distance_symbol = ((distance_symbol + u1) & MASK)
          end
          distance_wire = deflate_reverse_code(distance_symbol, u5)
          state = deflate_write_bits(state, distance_wire, u5)
          distance_base_final = distance_base(distance_symbol)
          distance_extra_final = distance_extra(distance_symbol)
          distance_value = ((distance_u - distance_base_final) & MASK)
          state = deflate_write_bits(state, distance_value, distance_extra_final)
        end
        is_literal = (!is_match)
        if is_literal
          literal_at = (pos + i1)
          literal = tokens.getbyte(literal_at)
          state = deflate_fixed_symbol(state, literal)
        end
        complete = deflate_drain_complete(state)
        complete_n = complete.bytesize
        drain_at = i0
        loop do
          drain_done = (drain_at >= complete_n)
          if drain_done
            break
          end
          drain_byte = complete.getbyte(drain_at)
          out << (drain_byte & 0xff)
          drain_at = (drain_at + i1)
        end
        state = deflate_drain_carry(state)
        pos = (pos + i5)
      end
      state = deflate_fixed_symbol(state, u256)
      state_n = state.bytesize
      tail_at = i1
      loop do
        tail_done = (tail_at >= state_n)
        if tail_done
          break
        end
        tail_byte = state.getbyte(tail_at)
        out << (tail_byte & 0xff)
        tail_at = (tail_at + i1)
      end
      return out
    end

    def deflate_u16_zeros(count)
      u0 = 0
      u1 = 1
      u2 = 2
      out = String.new(encoding: Encoding::BINARY)
      width = ((count * u2) & MASK)
      at = u0
      loop do
        done = (at >= width)
        if done
          break
        end
        out << (u0 & 0xff)
        at = ((at + u1) & MASK)
      end
      return out
    end

    def deflate_u16_get(data, index)
      i1 = 1
      u8 = 8
      u2 = 2
      offset_u = ((index * u2) & MASK)
      offset = u64_to_i64(offset_u)
      high_at = (offset + i1)
      low = data.getbyte(offset)
      high = data.getbyte(high_at)
      shifted = ((high << u8) & MASK)
      value = (low | shifted)
      return value
    end

    def deflate_u16_set(data, index, value)
      i1 = 1
      u2 = 2
      u8 = 8
      u255 = 255
      i0 = 0
      out = String.new(encoding: Encoding::BINARY)
      n = data.bytesize
      copy_at = i0
      loop do
        copy_done = (copy_at >= n)
        if copy_done
          break
        end
        copy_byte = data.getbyte(copy_at)
        out << (copy_byte & 0xff)
        copy_at = (copy_at + i1)
      end
      offset_u = ((index * u2) & MASK)
      offset = u64_to_i64(offset_u)
      high_at = (offset + i1)
      low = (value & u255)
      shifted = (value >> u8)
      high = (shifted & u255)
      out.setbyte(offset, low & 0xff)
      out.setbyte(high_at, high & 0xff)
      return out
    end

    def deflate_u16_increment(data, index, amount)
      u65535 = 65535
      old = deflate_u16_get(data, index)
      sum = ((old + amount) & MASK)
      wrapped = (sum & u65535)
      out = deflate_u16_set(data, index, wrapped)
      return out
    end

    def deflate_record_key_get(records, record)
      u2 = 2
      word = ((record * u2) & MASK)
      key = deflate_u16_get(records, word)
      return key
    end

    def deflate_record_key_set(records, record, key)
      u2 = 2
      word = ((record * u2) & MASK)
      out = deflate_u16_set(records, word, key)
      return out
    end

    def deflate_optimized_lengths(counts, table_len, limit)
      i0 = 0
      i1 = 1
      i2 = 2
      i3 = 3
      i4 = 4
      u0 = 0
      u1 = 1
      u2 = 2
      u4 = 4
      u8 = 8
      u33 = 33
      u255 = 255
      u65535 = 65535
      used = String.new(encoding: Encoding::BINARY)
      used_count = u0
      symbol = u0
      loop do
        done = (symbol >= table_len)
        if done
          break
        end
        frequency = deflate_u16_get(counts, symbol)
        present = (frequency != u0)
        if present
          frequency_low = (frequency & u255)
          frequency_shifted = (frequency >> u8)
          frequency_high = (frequency_shifted & u255)
          symbol_low = (symbol & u255)
          symbol_shifted = (symbol >> u8)
          symbol_high = (symbol_shifted & u255)
          used << (frequency_low & 0xff)
          used << (frequency_high & 0xff)
          used << (symbol_low & 0xff)
          used << (symbol_high & 0xff)
          used_count = ((used_count + u1) & MASK)
        end
        symbol = ((symbol + u1) & MASK)
      end
      used_count_i = u64_to_i64(used_count)
      chosen = String.new(encoding: Encoding::BINARY)
      chosen_at = u0
      loop do
        chosen_done = (chosen_at >= used_count)
        if chosen_done
          break
        end
        chosen << (u0 & 0xff)
        chosen_at = ((chosen_at + u1) & MASK)
      end
      sorted = String.new(encoding: Encoding::BINARY)
      slot = u0
      loop do
        sorted_done = (slot >= used_count)
        if sorted_done
          break
        end
        scan = u0
        best_index = u0
        best_frequency = u65535
        have_best = u0
        loop do
          scan_done = (scan >= used_count)
          if scan_done
            break
          end
          scan_i = u64_to_i64(scan)
          already = chosen.getbyte(scan_i)
          unchosen = (already == u0)
          if unchosen
            record_u = ((scan * u4) & MASK)
            scan_record = u64_to_i64(record_u)
            record_high = (scan_record + i1)
            low = used.getbyte(scan_record)
            high = used.getbyte(record_high)
            high_shifted = ((high << u8) & MASK)
            frequency = (low | high_shifted)
            first_candidate = (have_best == u0)
            lower = (frequency < best_frequency)
            take = (first_candidate || lower)
            if take
              best_index = scan
              best_frequency = frequency
              have_best = u1
            end
          end
          scan = ((scan + u1) & MASK)
        end
        best_i = u64_to_i64(best_index)
        chosen.setbyte(best_i, u1 & 0xff)
        best_record_u = ((best_index * u4) & MASK)
        best_record = u64_to_i64(best_record_u)
        copy_ = i0
        loop do
          copy_done = (copy_ >= i4)
          if copy_done
            break
          end
          source = (best_record + copy_)
          byte_ = used.getbyte(source)
          sorted << (byte_ & 0xff)
          copy_ = (copy_ + i1)
        end
        slot = ((slot + u1) & MASK)
      end
      one = (used_count == u1)
      if one
        sorted.setbyte(i0, u1 & 0xff)
        sorted.setbyte(i1, u0 & 0xff)
      end
      many = (used_count > u1)
      if many
        f0 = deflate_record_key_get(sorted, u0)
        f1 = deflate_record_key_get(sorted, u1)
        initial_sum = ((f0 + f1) & MASK)
        initial_wrapped = (initial_sum & u65535)
        sorted = deflate_record_key_set(sorted, u0, initial_wrapped)
        root = u0
        leaf = u2
        next_ = u1
        last_internal = ((used_count - u1) & MASK)
        loop do
          merge_done = (next_ >= last_internal)
          if merge_done
            break
          end
          leaf_end = (leaf >= used_count)
          take_root = leaf_end
          leaf_available = (!leaf_end)
          if leaf_available
            root_key = deflate_record_key_get(sorted, root)
            leaf_key = deflate_record_key_get(sorted, leaf)
            root_lower = (root_key < leaf_key)
            take_root = root_lower
          end
          if take_root
            root_key = deflate_record_key_get(sorted, root)
            sorted = deflate_record_key_set(sorted, next_, root_key)
            sorted = deflate_record_key_set(sorted, root, next_)
            root = ((root + u1) & MASK)
          end
          take_leaf = (!take_root)
          if take_leaf
            leaf_key = deflate_record_key_get(sorted, leaf)
            sorted = deflate_record_key_set(sorted, next_, leaf_key)
            leaf = ((leaf + u1) & MASK)
          end
          leaf_end2 = (leaf >= used_count)
          take_root2 = leaf_end2
          leaf_available2 = (!leaf_end2)
          if leaf_available2
            root_before_next = (root < next_)
            if root_before_next
              root_key2 = deflate_record_key_get(sorted, root)
              leaf_key2 = deflate_record_key_get(sorted, leaf)
              root_lower2 = (root_key2 < leaf_key2)
              take_root2 = root_lower2
            end
          end
          next_key = deflate_record_key_get(sorted, next_)
          if take_root2
            root_key2 = deflate_record_key_get(sorted, root)
            combined = ((next_key + root_key2) & MASK)
            combined_wrapped = (combined & u65535)
            sorted = deflate_record_key_set(sorted, next_, combined_wrapped)
            sorted = deflate_record_key_set(sorted, root, next_)
            root = ((root + u1) & MASK)
          end
          take_leaf2 = (!take_root2)
          if take_leaf2
            leaf_key2 = deflate_record_key_get(sorted, leaf)
            combined = ((next_key + leaf_key2) & MASK)
            combined_wrapped = (combined & u65535)
            sorted = deflate_record_key_set(sorted, next_, combined_wrapped)
            leaf = ((leaf + u1) & MASK)
          end
          next_ = ((next_ + u1) & MASK)
        end
        n_minus2 = ((used_count - u2) & MASK)
        sorted = deflate_record_key_set(sorted, n_minus2, u0)
        back = n_minus2
        loop do
          back_done = (back == u0)
          if back_done
            break
          end
          back = ((back - u1) & MASK)
          parent = deflate_record_key_get(sorted, back)
          parent_depth = deflate_record_key_get(sorted, parent)
          depth = ((parent_depth + u1) & MASK)
          sorted = deflate_record_key_set(sorted, back, depth)
        end
        slots_available = u1
        used_here = u0
        depth = u0
        root_i = u64_to_i64(n_minus2)
        next_i = (used_count_i - i1)
        loop do
          assign_done = (slots_available == u0)
          if assign_done
            break
          end
          loop do
            root_negative = (root_i < i0)
            if root_negative
              break
            end
            root_u = (root_i & MASK)
            root_depth = deflate_record_key_get(sorted, root_u)
            different_depth = (root_depth != depth)
            if different_depth
              break
            end
            used_here = ((used_here + u1) & MASK)
            root_i = (root_i - i1)
          end
          loop do
            enough = (slots_available <= used_here)
            if enough
              break
            end
            next_u = (next_i & MASK)
            sorted = deflate_record_key_set(sorted, next_u, depth)
            next_i = (next_i - i1)
            slots_available = ((slots_available - u1) & MASK)
          end
          slots_available = ((used_here * u2) & MASK)
          depth = ((depth + u1) & MASK)
          used_here = u0
        end
      end
      num_codes = deflate_u16_zeros(u33)
      count_record = u0
      loop do
        count_record_done = (count_record >= used_count)
        if count_record_done
          break
        end
        count_depth = deflate_record_key_get(sorted, count_record)
        num_codes = deflate_u16_increment(num_codes, count_depth, u1)
        count_record = ((count_record + u1) & MASK)
      end
      over = ((limit + u1) & MASK)
      over_sum = u0
      loop do
        over_done = (over >= u33)
        if over_done
          break
        end
        amount = deflate_u16_get(num_codes, over)
        over_sum = ((over_sum + amount) & MASK)
        over = ((over + u1) & MASK)
      end
      limit_count = deflate_u16_get(num_codes, limit)
      limit_total = ((limit_count + over_sum) & MASK)
      num_codes = deflate_u16_set(num_codes, limit, limit_total)
      total = u0
      width = u1
      loop do
        width_done = (width > limit)
        if width_done
          break
        end
        count = deflate_u16_get(num_codes, width)
        shift = ((limit - width) & MASK)
        weighted = ((count << shift) & MASK)
        total = ((total + weighted) & MASK)
        width = ((width + u1) & MASK)
      end
      capacity = ((u1 << limit) & MASK)
      loop do
        balanced = (total <= capacity)
        if balanced
          break
        end
        limit_count = deflate_u16_get(num_codes, limit)
        limit_less = ((limit_count - u1) & MASK)
        num_codes = deflate_u16_set(num_codes, limit, limit_less)
        seek = ((limit - u1) & MASK)
        loop do
          seek_count = deflate_u16_get(num_codes, seek)
          found = (seek_count != u0)
          if found
            seek_less = ((seek_count - u1) & MASK)
            num_codes = deflate_u16_set(num_codes, seek, seek_less)
            deeper = ((seek + u1) & MASK)
            deeper_count = deflate_u16_get(num_codes, deeper)
            deeper_more = ((deeper_count + u2) & MASK)
            num_codes = deflate_u16_set(num_codes, deeper, deeper_more)
            break
          end
          seek = ((seek - u1) & MASK)
        end
        total = ((total - u1) & MASK)
      end
      lengths = String.new(encoding: Encoding::BINARY)
      fill = u0
      loop do
        fill_done = (fill >= table_len)
        if fill_done
          break
        end
        lengths << (u0 & 0xff)
        fill = ((fill + u1) & MASK)
      end
      last = used_count
      width = u1
      loop do
        width_done = (width > limit)
        if width_done
          break
        end
        amount = deflate_u16_get(num_codes, width)
        length_first = ((last - amount) & MASK)
        length_record = length_first
        loop do
          length_record_done = (length_record >= last)
          if length_record_done
            break
          end
          record_base_u = ((length_record * u4) & MASK)
          record_base = u64_to_i64(record_base_u)
          symbol_low_at = (record_base + i2)
          symbol_high_at = (record_base + i3)
          symbol_low = sorted.getbyte(symbol_low_at)
          symbol_high = sorted.getbyte(symbol_high_at)
          symbol_high_shifted = ((symbol_high << u8) & MASK)
          symbol_u = (symbol_low | symbol_high_shifted)
          symbol_i = u64_to_i64(symbol_u)
          lengths.setbyte(symbol_i, width & 0xff)
          length_record = ((length_record + u1) & MASK)
        end
        last = length_first
        width = ((width + u1) & MASK)
      end
      return lengths
    end

    def deflate_canonical_codes(lengths, max_bits)
      i0 = 0
      i1 = 1
      u0 = 0
      u1 = 1
      counts = deflate_u16_zeros(max_bits)
      counts_head = String.new(encoding: Encoding::BINARY)
      counts_head << (u0 & 0xff)
      counts_head << (u0 & 0xff)
      counts = append_bytes(counts_head, counts)
      n = lengths.bytesize
      at = i0
      loop do
        count_done = (at >= n)
        if count_done
          break
        end
        width = lengths.getbyte(at)
        coded = (width != u0)
        if coded
          counts = deflate_u16_increment(counts, width, u1)
        end
        at = (at + i1)
      end
      next_count = ((max_bits + u1) & MASK)
      next_ = deflate_u16_zeros(next_count)
      code = u0
      width = 2
      loop do
        next_done = (width > max_bits)
        if next_done
          break
        end
        previous = ((width - u1) & MASK)
        previous_count = deflate_u16_get(counts, previous)
        sum = ((code + previous_count) & MASK)
        code = ((sum << u1) & MASK)
        next_ = deflate_u16_set(next_, width, code)
        width = ((width + u1) & MASK)
      end
      n_u = (n & MASK)
      codes = deflate_u16_zeros(n_u)
      symbol = i0
      loop do
        codes_done = (symbol >= n)
        if codes_done
          break
        end
        width = lengths.getbyte(symbol)
        coded = (width != u0)
        if coded
          canonical = deflate_u16_get(next_, width)
          wire = deflate_reverse_code(canonical, width)
          symbol_u = (symbol & MASK)
          codes = deflate_u16_set(codes, symbol_u, wire)
          canonical_next = ((canonical + u1) & MASK)
          next_ = deflate_u16_set(next_, width, canonical_next)
        end
        symbol = (symbol + i1)
      end
      return codes
    end

    def deflate_pack_code_lengths(lengths)
      i0 = 0
      i1 = 1
      u0 = 0
      u1 = 1
      u3 = 3
      u6 = 6
      u10 = 10
      u11 = 11
      u16 = 16
      u17 = 17
      u18 = 18
      u19 = 19
      u138 = 138
      counts = deflate_u16_zeros(u19)
      packed_ = String.new(encoding: Encoding::BINARY)
      n = lengths.bytesize
      at = i0
      loop do
        done = (at >= n)
        if done
          break
        end
        width = lengths.getbyte(at)
        zero = (width == u0)
        if zero
          run = u1
          scan = (at + i1)
          loop do
            scan_end = (scan >= n)
            run_full = (run >= u138)
            stop = (scan_end || run_full)
            if stop
              break
            end
            next_width = lengths.getbyte(scan)
            different = (next_width != u0)
            if different
              break
            end
            run = ((run + u1) & MASK)
            scan = (scan + i1)
          end
          short_ = (run < u3)
          if short_
            left = run
            loop do
              emitted = (left == u0)
              if emitted
                break
              end
              packed_ << (u0 & 0xff)
              counts = deflate_u16_increment(counts, u0, u1)
              left = ((left - u1) & MASK)
            end
          end
          not_short = (!short_)
          if not_short
            medium = (run <= u10)
            if medium
              packed_ << (u17 & 0xff)
              extra = ((run - u3) & MASK)
              packed_ << (extra & 0xff)
              counts = deflate_u16_increment(counts, u17, u1)
            end
            long_ = (!medium)
            if long_
              packed_ << (u18 & 0xff)
              extra = ((run - u11) & MASK)
              packed_ << (extra & 0xff)
              counts = deflate_u16_increment(counts, u18, u1)
            end
          end
          run_i = u64_to_i64(run)
          at = (at + run_i)
        end
        nonzero = (!zero)
        if nonzero
          packed_ << (width & 0xff)
          counts = deflate_u16_increment(counts, width, u1)
          at = (at + i1)
          repeat = u0
          loop do
            repeat_done = (at >= n)
            if repeat_done
              break
            end
            next_width = lengths.getbyte(at)
            different = (next_width != width)
            if different
              break
            end
            repeat = ((repeat + u1) & MASK)
            at = (at + i1)
            chunk_full = (repeat == u6)
            if chunk_full
              packed_ << (u16 & 0xff)
              extra = ((repeat - u3) & MASK)
              packed_ << (extra & 0xff)
              counts = deflate_u16_increment(counts, u16, u1)
              repeat = u0
            end
          end
          repeat_short = (repeat < u3)
          if repeat_short
            left = repeat
            loop do
              emitted = (left == u0)
              if emitted
                break
              end
              packed_ << (width & 0xff)
              counts = deflate_u16_increment(counts, width, u1)
              left = ((left - u1) & MASK)
            end
          end
          repeat_long = (repeat >= u3)
          if repeat_long
            packed_ << (u16 & 0xff)
            extra = ((repeat - u3) & MASK)
            packed_ << (extra & 0xff)
            counts = deflate_u16_increment(counts, u16, u1)
          end
        end
      end
      out = append_bytes(counts, packed_)
      return out
    end

    def deflate_huffman_symbol(state, codes, lengths, symbol)
      symbol_i = u64_to_i64(symbol)
      width = lengths.getbyte(symbol_i)
      code = deflate_u16_get(codes, symbol)
      out = deflate_write_bits(state, code, width)
      return out
    end

    def deflate_match_symbols(length, distance)
      u0 = 0
      u1 = 1
      u30 = 30
      u32 = 32
      u257 = 257
      u258 = 258
      u285 = 285
      length_symbol = u257
      loop do
        last_length = (length_symbol >= u285)
        if last_length
          break
        end
        base = length_base(length_symbol)
        extra_count = length_extra(length_symbol)
        span = ((u1 << extra_count) & MASK)
        upper = ((base + span) & MASK)
        fits = (length < upper)
        if fits
          break
        end
        length_symbol = ((length_symbol + u1) & MASK)
      end
      maximum_length = (length == u258)
      if maximum_length
        length_symbol = u285
      end
      distance_symbol = u0
      loop do
        last_distance = (distance_symbol >= u30)
        if last_distance
          break
        end
        base = distance_base(distance_symbol)
        extra_count = distance_extra(distance_symbol)
        span = ((u1 << extra_count) & MASK)
        upper = ((base + span) & MASK)
        fits = (distance < upper)
        if fits
          break
        end
        distance_symbol = ((distance_symbol + u1) & MASK)
      end
      length_high = ((length_symbol << u32) & MASK)
      packed_ = (length_high | distance_symbol)
      return packed_
    end

    def deflate_dynamic(data)
      i0 = 0
      i1 = 1
      i2 = 2
      i3 = 3
      i4 = 4
      i5 = 5
      i38 = 38
      u0 = 0
      u1 = 1
      u2 = 2
      u3 = 3
      u4 = 4
      u5 = 5
      u7 = 7
      u8 = 8
      u15 = 15
      u16 = 16
      u19 = 19
      u30 = 30
      u32 = 32
      u256 = 256
      u257 = 257
      u286 = 286
      u288 = 288
      u4294967295 = 4294967295
      tokens = deflate_tokens(data)
      lit_counts = deflate_u16_zeros(u288)
      dist_counts = deflate_u16_zeros(u32)
      tokens_n = tokens.bytesize
      token_at = i0
      loop do
        count_done = (token_at >= tokens_n)
        if count_done
          break
        end
        tag = tokens.getbyte(token_at)
        match_ = (tag == u1)
        if match_
          value_low_at = (token_at + i1)
          value_high_at = (token_at + i2)
          distance_low_at = (token_at + i3)
          distance_high_at = (token_at + i4)
          value_low = tokens.getbyte(value_low_at)
          value_high = tokens.getbyte(value_high_at)
          value_high_shifted = ((value_high << u8) & MASK)
          length = (value_low | value_high_shifted)
          distance_low = tokens.getbyte(distance_low_at)
          distance_high = tokens.getbyte(distance_high_at)
          distance_high_shifted = ((distance_high << u8) & MASK)
          distance = (distance_low | distance_high_shifted)
          symbols = deflate_match_symbols(length, distance)
          length_symbol = (symbols >> u32)
          distance_symbol = (symbols & u4294967295)
          lit_counts = deflate_u16_increment(lit_counts, length_symbol, u1)
          dist_counts = deflate_u16_increment(dist_counts, distance_symbol, u1)
        end
        literal = (!match_)
        if literal
          literal_at = (token_at + i1)
          literal_symbol = tokens.getbyte(literal_at)
          lit_counts = deflate_u16_increment(lit_counts, literal_symbol, u1)
        end
        token_at = (token_at + i5)
      end
      lit_counts = deflate_u16_set(lit_counts, u256, u1)
      lit_lengths = deflate_optimized_lengths(lit_counts, u288, u15)
      dist_lengths = deflate_optimized_lengths(dist_counts, u32, u15)
      lit_codes = deflate_canonical_codes(lit_lengths, u15)
      dist_codes = deflate_canonical_codes(dist_lengths, u15)
      num_lit = u286
      loop do
        minimum_lit = (num_lit <= u257)
        if minimum_lit
          break
        end
        last_lit = ((num_lit - u1) & MASK)
        last_lit_i = u64_to_i64(last_lit)
        last_width = lit_lengths.getbyte(last_lit_i)
        used_lit = (last_width != u0)
        if used_lit
          break
        end
        num_lit = last_lit
      end
      num_dist = u30
      loop do
        minimum_dist = (num_dist <= u1)
        if minimum_dist
          break
        end
        last_dist = ((num_dist - u1) & MASK)
        last_dist_i = u64_to_i64(last_dist)
        last_width = dist_lengths.getbyte(last_dist_i)
        used_dist = (last_width != u0)
        if used_dist
          break
        end
        num_dist = last_dist
      end
      num_lit_i = u64_to_i64(num_lit)
      num_dist_i = u64_to_i64(num_dist)
      packed_lit_lengths = lit_lengths.byteslice(i0, num_lit_i - i0).dup
      packed_dist_lengths = dist_lengths.byteslice(i0, num_dist_i - i0).dup
      sizes = append_bytes(packed_lit_lengths, packed_dist_lengths)
      packed_bundle = deflate_pack_code_lengths(sizes)
      bundle_n = packed_bundle.bytesize
      cl_counts = packed_bundle.byteslice(i0, i38 - i0).dup
      packed_ = packed_bundle.byteslice(i38, bundle_n - i38).dup
      cl_lengths = deflate_optimized_lengths(cl_counts, u19, u7)
      cl_codes = deflate_canonical_codes(cl_lengths, u7)
      order = code_length_order()
      num_bit_lengths = u19
      loop do
        minimum_cl = (num_bit_lengths <= u4)
        if minimum_cl
          break
        end
        order_at = ((num_bit_lengths - u1) & MASK)
        order_at_i = u64_to_i64(order_at)
        cl_symbol = order.getbyte(order_at_i)
        cl_symbol_i = u64_to_i64(cl_symbol)
        cl_width = cl_lengths.getbyte(cl_symbol_i)
        used_cl = (cl_width != u0)
        if used_cl
          break
        end
        num_bit_lengths = order_at
      end
      out = String.new(encoding: Encoding::BINARY)
      state = String.new(encoding: Encoding::BINARY)
      state << (u0 & 0xff)
      state = deflate_write_bits(state, u5, u3)
      hlit = ((num_lit - u257) & MASK)
      hdist = ((num_dist - u1) & MASK)
      hclen = ((num_bit_lengths - u4) & MASK)
      state = deflate_write_bits(state, hlit, u5)
      state = deflate_write_bits(state, hdist, u5)
      state = deflate_write_bits(state, hclen, u4)
      order_at = u0
      loop do
        order_done = (order_at >= num_bit_lengths)
        if order_done
          break
        end
        order_at_i = u64_to_i64(order_at)
        cl_symbol = order.getbyte(order_at_i)
        cl_symbol_i = u64_to_i64(cl_symbol)
        cl_width = cl_lengths.getbyte(cl_symbol_i)
        state = deflate_write_bits(state, cl_width, u3)
        order_at = ((order_at + u1) & MASK)
      end
      packed_n = packed_.bytesize
      packed_at = i0
      loop do
        packed_done = (packed_at >= packed_n)
        if packed_done
          break
        end
        cl_symbol = packed_.getbyte(packed_at)
        state = deflate_huffman_symbol(state, cl_codes, cl_lengths, cl_symbol)
        packed_at = (packed_at + i1)
        has_extra = (cl_symbol >= u16)
        if has_extra
          extra = packed_.getbyte(packed_at)
          extra_index = ((cl_symbol - u16) & MASK)
          extra_width = u2
          is17 = (extra_index == u1)
          if is17
            extra_width = u3
          end
          is18 = (extra_index == u2)
          if is18
            extra_width = u7
          end
          state = deflate_write_bits(state, extra, extra_width)
          packed_at = (packed_at + i1)
        end
      end
      token_at = i0
      loop do
        emit_done = (token_at >= tokens_n)
        if emit_done
          break
        end
        tag = tokens.getbyte(token_at)
        match_ = (tag == u1)
        if match_
          value_low_at = (token_at + i1)
          value_high_at = (token_at + i2)
          distance_low_at = (token_at + i3)
          distance_high_at = (token_at + i4)
          value_low = tokens.getbyte(value_low_at)
          value_high = tokens.getbyte(value_high_at)
          value_high_shifted = ((value_high << u8) & MASK)
          length = (value_low | value_high_shifted)
          distance_low = tokens.getbyte(distance_low_at)
          distance_high = tokens.getbyte(distance_high_at)
          distance_high_shifted = ((distance_high << u8) & MASK)
          distance = (distance_low | distance_high_shifted)
          symbols = deflate_match_symbols(length, distance)
          length_symbol = (symbols >> u32)
          distance_symbol = (symbols & u4294967295)
          state = deflate_huffman_symbol(state, lit_codes, lit_lengths, length_symbol)
          length_base_value = length_base(length_symbol)
          length_extra_width = length_extra(length_symbol)
          length_extra_value = ((length - length_base_value) & MASK)
          state = deflate_write_bits(state, length_extra_value, length_extra_width)
          state = deflate_huffman_symbol(state, dist_codes, dist_lengths, distance_symbol)
          distance_base_value = distance_base(distance_symbol)
          distance_extra_width = distance_extra(distance_symbol)
          distance_extra_value = ((distance - distance_base_value) & MASK)
          state = deflate_write_bits(state, distance_extra_value, distance_extra_width)
        end
        literal = (!match_)
        if literal
          literal_at = (token_at + i1)
          literal_symbol = tokens.getbyte(literal_at)
          state = deflate_huffman_symbol(state, lit_codes, lit_lengths, literal_symbol)
        end
        complete = deflate_drain_complete(state)
        complete_n = complete.bytesize
        drain_at = i0
        loop do
          drain_done = (drain_at >= complete_n)
          if drain_done
            break
          end
          drain_byte = complete.getbyte(drain_at)
          out << (drain_byte & 0xff)
          drain_at = (drain_at + i1)
        end
        state = deflate_drain_carry(state)
        token_at = (token_at + i5)
      end
      state = deflate_huffman_symbol(state, lit_codes, lit_lengths, u256)
      state_n = state.bytesize
      tail_at = i1
      loop do
        tail_done = (tail_at >= state_n)
        if tail_done
          break
        end
        tail_byte = state.getbyte(tail_at)
        out << (tail_byte & 0xff)
        tail_at = (tail_at + i1)
      end
      return out
    end

    def deflate_stored(data)
      u1 = 1
      u8 = 8
      u255 = 255
      u65535 = 65535
      head = String.new(encoding: Encoding::BINARY)
      head << (u1 & 0xff)
      n_i = data.bytesize
      n = (n_i & MASK)
      n_low = (n & u255)
      n_shifted = (n >> u8)
      n_high = (n_shifted & u255)
      complement = ((u65535 - n) & MASK)
      complement_low = (complement & u255)
      complement_shifted = (complement >> u8)
      complement_high = (complement_shifted & u255)
      head << (n_low & 0xff)
      head << (n_high & 0xff)
      head << (complement_low & 0xff)
      head << (complement_high & 0xff)
      out = append_bytes(head, data)
      return out
    end

    def deflate_miniz_level6(data)
      i0 = 0
      i32 = 32
      i48 = 48
      i65535 = 65535
      n = data.bytesize
      body = data.byteslice(i0, i0 - i0).dup
      fixed = (n < i48)
      if fixed
        body = deflate_fixed(data)
      end
      dynamic = (n >= i48)
      if dynamic
        body = deflate_dynamic(data)
      end
      body_n = body.bytesize
      large = (n > i32)
      expanded = (body_n >= n)
      fits_stored = (n <= i65535)
      fallback_candidate = (large && expanded)
      fallback = (fallback_candidate && fits_stored)
      if fallback
        body = deflate_stored(data)
      end
      return body
    end

    def zlib_compress(data)
      u8 = 8
      u16 = 16
      u24 = 24
      u120 = 120
      u156 = 156
      u255 = 255
      out = String.new(encoding: Encoding::BINARY)
      out << (u120 & 0xff)
      out << (u156 & 0xff)
      body = deflate_miniz_level6(data)
      prefixed = append_bytes(out, body)
      checksum = adler32(data)
      b3_shifted = (checksum >> u24)
      b3 = (b3_shifted & u255)
      b2_shifted = (checksum >> u16)
      b2 = (b2_shifted & u255)
      b1_shifted = (checksum >> u8)
      b1 = (b1_shifted & u255)
      b0 = (checksum & u255)
      trailer = String.new(encoding: Encoding::BINARY)
      trailer << (b3 & 0xff)
      trailer << (b2 & 0xff)
      trailer << (b1 & 0xff)
      trailer << (b0 & 0xff)
      complete = append_bytes(prefixed, trailer)
      return complete
    end

    def append_bytes(left, right)
      out = String.new(encoding: Encoding::BINARY)
      i0 = 0
      i1 = 1
      left_n = left.bytesize
      right_n = right.bytesize
      pos = i0
      loop do
        done = (pos >= left_n)
        if done
          break
        end
        byte_ = left.getbyte(pos)
        out << (byte_ & 0xff)
        pos = (pos + i1)
      end
      pos = i0
      loop do
        done = (pos >= right_n)
        if done
          break
        end
        byte_ = right.getbyte(pos)
        out << (byte_ & 0xff)
        pos = (pos + i1)
      end
      return out
    end

    def u32_to_le(value)
      out = String.new(encoding: Encoding::BINARY)
      u8 = 8
      u255 = 255
      u4 = 4
      pos = 0
      remaining = value
      loop do
        done = (pos >= u4)
        if done
          break
        end
        byte_ = (remaining & u255)
        out << (byte_ & 0xff)
        remaining = (remaining >> u8)
        one = 1
        pos = ((pos + one) & MASK)
      end
      return out
    end

    def u64_to_le(value)
      out = String.new(encoding: Encoding::BINARY)
      u8 = 8
      u255 = 255
      count = 8
      pos = 0
      remaining = value
      loop do
        done = (pos >= count)
        if done
          break
        end
        byte_ = (remaining & u255)
        out << (byte_ & 0xff)
        remaining = (remaining >> u8)
        one = 1
        pos = ((pos + one) & MASK)
      end
      return out
    end

    def read_u32_le(data, start)
      u0 = 0
      u8 = 8
      i0 = 0
      i1 = 1
      i4 = 4
      result = u0
      shift = u0
      pos = start
      read = i0
      loop do
        done = (read >= i4)
        if done
          break
        end
        byte_ = data.getbyte(pos)
        part = ((byte_ << shift) & MASK)
        result = (result | part)
        shift = ((shift + u8) & MASK)
        pos = (pos + i1)
        read = (read + i1)
      end
      return result
    end

    def read_u64_le(data, start)
      u0 = 0
      u8 = 8
      i0 = 0
      i1 = 1
      i8 = 8
      result = u0
      shift = u0
      pos = start
      read = i0
      loop do
        done = (read >= i8)
        if done
          break
        end
        byte_ = data.getbyte(pos)
        part = ((byte_ << shift) & MASK)
        result = (result | part)
        shift = ((shift + u8) & MASK)
        pos = (pos + i1)
        read = (read + i1)
      end
      return result
    end

    def bounded_advance(data, start, amount)
      i0 = 0
      negative = (start < i0)
      if negative
        return i0
      end
      amount_i64 = u64_to_i64(amount)
      end_ = (start + amount_i64)
      n = data.bytesize
      inside = (end_ <= n)
      if inside
        return end_
      end
      return i0
    end

    def choice_list_header(count)
      header = u32_to_le(count)
      return header
    end

    def serialize_integer_choice(value_raw)
      out = String.new(encoding: Encoding::BINARY)
      tag = 0
      subtag = 10
      out << (tag & 0xff)
      out << (subtag & 0xff)
      value = canonicalize_signed_le(value_raw)
      length_i64 = value.bytesize
      length = (length_i64 & MASK)
      length_bytes = u32_to_le(length)
      with_length = append_bytes(out, length_bytes)
      encoded = append_bytes(with_length, value)
      return encoded
    end

    def serialize_boolean_choice(value)
      out = String.new(encoding: Encoding::BINARY)
      tag = 1
      byte_ = 0
      if value
        byte_ = 1
      end
      out << (tag & 0xff)
      out << (byte_ & 0xff)
      return out
    end

    def serialize_float_choice(value)
      out = String.new(encoding: Encoding::BINARY)
      tag = 2
      out << (tag & 0xff)
      bits = f2bits(value)
      raw = u64_to_le(bits)
      encoded = append_bytes(out, raw)
      return encoded
    end

    def serialize_bytes_choice(value)
      out = String.new(encoding: Encoding::BINARY)
      tag = 3
      out << (tag & 0xff)
      length_i64 = value.bytesize
      length = (length_i64 & MASK)
      length_bytes = u32_to_le(length)
      with_length = append_bytes(out, length_bytes)
      encoded = append_bytes(with_length, value)
      return encoded
    end

    def serialize_string_choice_packed(count, codepoints_le)
      out = String.new(encoding: Encoding::BINARY)
      tag = 4
      out << (tag & 0xff)
      length_bytes = u32_to_le(count)
      with_length = append_bytes(out, length_bytes)
      encoded = append_bytes(with_length, codepoints_le)
      return encoded
    end

    def serialize_clone_header(child_count)
      out = String.new(encoding: Encoding::BINARY)
      tag = 5
      out << (tag & 0xff)
      header = choice_list_header(child_count)
      encoded = append_bytes(out, header)
      return encoded
    end

    def serialize_keyed_choice(key, inner)
      out = String.new(encoding: Encoding::BINARY)
      tag = 6
      out << (tag & 0xff)
      key_bytes = u64_to_le(key)
      with_key = append_bytes(out, key_bytes)
      encoded = append_bytes(with_key, inner)
      return encoded
    end

    def keyed_entry_key(data, start)
      i0 = 0
      i1 = 1
      u6 = 6
      u8 = 8
      none = nil
      n = data.bytesize
      start_negative = (start < i0)
      if start_negative
        return none
      end
      missing_tag = (start >= n)
      if missing_tag
        return none
      end
      tag = data.getbyte(start)
      keyed = (tag == u6)
      unkeyed = (!keyed)
      if unkeyed
        return none
      end
      key_start = (start + i1)
      key_end = bounded_advance(data, key_start, u8)
      truncated = (key_end == i0)
      if truncated
        return none
      end
      key = read_u64_le(data, key_start)
      found = key
      return found
    end

    def keyed_entry_inner(data, start)
      i0 = 0
      i1 = 1
      u8 = 8
      key = keyed_entry_key(data, start)
      present = !key.nil?
      absent = (!present)
      if absent
        return i0
      end
      key_start = (start + i1)
      inner = bounded_advance(data, key_start, u8)
      return inner
    end

    def choice_entry_end(data, start, depth)
      i0 = 0
      i1 = 1
      u0 = 0
      u1 = 1
      u2 = 2
      u4 = 4
      u8 = 8
      u16 = 16
      u100 = 100
      too_deep = (depth > u100)
      if too_deep
        return i0
      end
      n = data.bytesize
      start_negative = (start < i0)
      if start_negative
        return i0
      end
      missing_tag = (start >= n)
      if missing_tag
        return i0
      end
      tag = data.getbyte(start)
      value_start = (start + i1)
      integer = (tag == u0)
      if integer
        sub_end = bounded_advance(data, value_start, u1)
        sub_missing = (sub_end == i0)
        if sub_missing
          return i0
        end
        sub = data.getbyte(value_start)
        sub0 = (sub == u0)
        if sub0
          end_ = bounded_advance(data, sub_end, u1)
          return end_
        end
        sub1 = (sub == u1)
        if sub1
          end_ = bounded_advance(data, sub_end, u2)
          return end_
        end
        sub2 = (sub == u2)
        if sub2
          end_ = bounded_advance(data, sub_end, u4)
          return end_
        end
        u3 = 3
        sub3 = (sub == u3)
        if sub3
          end_ = bounded_advance(data, sub_end, u8)
          return end_
        end
        sub4 = (sub == u4)
        if sub4
          end_ = bounded_advance(data, sub_end, u16)
          return end_
        end
        u5 = 5
        sub5 = (sub == u5)
        if sub5
          end_ = bounded_advance(data, sub_end, u1)
          return end_
        end
        u6 = 6
        sub6 = (sub == u6)
        if sub6
          end_ = bounded_advance(data, sub_end, u2)
          return end_
        end
        u7 = 7
        sub7 = (sub == u7)
        if sub7
          end_ = bounded_advance(data, sub_end, u4)
          return end_
        end
        sub8 = (sub == u8)
        if sub8
          end_ = bounded_advance(data, sub_end, u8)
          return end_
        end
        u9 = 9
        sub9 = (sub == u9)
        if sub9
          end_ = bounded_advance(data, sub_end, u16)
          return end_
        end
        u10 = 10
        sub10 = (sub == u10)
        if sub10
          header_end = bounded_advance(data, sub_end, u4)
          header_missing = (header_end == i0)
          if header_missing
            return i0
          end
          length = read_u32_le(data, sub_end)
          end_ = bounded_advance(data, header_end, length)
          return end_
        end
        return i0
      end
      boolean_ = (tag == u1)
      if boolean_
        end_ = bounded_advance(data, value_start, u1)
        return end_
      end
      float_ = (tag == u2)
      if float_
        end_ = bounded_advance(data, value_start, u8)
        return end_
      end
      u3 = 3
      bytes = (tag == u3)
      if bytes
        header_end = bounded_advance(data, value_start, u4)
        header_missing = (header_end == i0)
        if header_missing
          return i0
        end
        length = read_u32_le(data, value_start)
        end_ = bounded_advance(data, header_end, length)
        return end_
      end
      string_ = (tag == u4)
      if string_
        header_end = bounded_advance(data, value_start, u4)
        header_missing = (header_end == i0)
        if header_missing
          return i0
        end
        length = read_u32_le(data, value_start)
        byte_length = ((length * u4) & MASK)
        end_ = bounded_advance(data, header_end, byte_length)
        return end_
      end
      u6 = 6
      keyed = (tag == u6)
      if keyed
        inner = bounded_advance(data, value_start, u8)
        truncated = (inner == i0)
        if truncated
          return i0
        end
        nested_key = keyed_entry_key(data, inner)
        double_keyed = !nested_key.nil?
        if double_keyed
          return i0
        end
        end_ = choice_entry_end(data, inner, depth)
        return end_
      end
      u5 = 5
      clone = (tag == u5)
      if clone
        header_end = bounded_advance(data, value_start, u4)
        header_missing = (header_end == i0)
        if header_missing
          return i0
        end
        count = read_u32_le(data, value_start)
        child_pos = header_end
        child_index = u0
        child_depth = ((depth + u1) & MASK)
        loop do
          done = (child_index >= count)
          if done
            break
          end
          child_end = choice_entry_end(data, child_pos, child_depth)
          child_invalid = (child_end == i0)
          if child_invalid
            return i0
          end
          child_pos = child_end
          child_index = ((child_index + u1) & MASK)
        end
        return child_pos
      end
      return i0
    end

    def choice_stream_validate(data)
      i0 = 0
      i4 = 4
      u0 = 0
      u1 = 1
      u4 = 4
      header_end = bounded_advance(data, i0, u4)
      header_missing = (header_end == i0)
      if header_missing
        invalid = false
        return invalid
      end
      count = read_u32_le(data, i0)
      pos = i4
      index = u0
      loop do
        done = (index >= count)
        if done
          break
        end
        end_ = choice_entry_end(data, pos, u0)
        invalid_entry = (end_ == i0)
        if invalid_entry
          invalid = false
          return invalid
        end
        pos = end_
        index = ((index + u1) & MASK)
      end
      valid = true
      return valid
    end

    def choice_stream_count(data)
      i0 = 0
      count = read_u32_le(data, i0)
      return count
    end

    def deserialize_integer_choice(data, start)
      i0 = 0
      i1 = 1
      i6 = 6
      u0 = 0
      u10 = 10
      end_ = choice_entry_end(data, start, u0)
      invalid = (end_ == i0)
      if invalid
        none = nil
        return none
      end
      tag = data.getbyte(start)
      wrong_tag = (tag != u0)
      if wrong_tag
        none = nil
        return none
      end
      sub_pos = (start + i1)
      sub = data.getbyte(sub_pos)
      wrong_sub = (sub != u10)
      if wrong_sub
        none = nil
        return none
      end
      value_start = (start + i6)
      value = data.byteslice(value_start, end_ - value_start).dup
      canonical = canonicalize_signed_le(value)
      some = canonical.dup
      return some
    end

    def deserialize_boolean_choice(data, start)
      i0 = 0
      i1 = 1
      u0 = 0
      u1 = 1
      end_ = choice_entry_end(data, start, u0)
      invalid = (end_ == i0)
      if invalid
        none = nil
        return none
      end
      tag = data.getbyte(start)
      wrong_tag = (tag != u1)
      if wrong_tag
        none = nil
        return none
      end
      value_pos = (start + i1)
      byte_ = data.getbyte(value_pos)
      value = (byte_ != u0)
      some = value
      return some
    end

    def deserialize_float_choice(data, start)
      i0 = 0
      i1 = 1
      u0 = 0
      u2 = 2
      end_ = choice_entry_end(data, start, u0)
      invalid = (end_ == i0)
      if invalid
        none = nil
        return none
      end
      tag = data.getbyte(start)
      wrong_tag = (tag != u2)
      if wrong_tag
        none = nil
        return none
      end
      value_pos = (start + i1)
      bits = read_u64_le(data, value_pos)
      value = bits2f(bits)
      some = value
      return some
    end

    def deserialize_bytes_choice(data, start)
      i0 = 0
      i5 = 5
      u0 = 0
      u3 = 3
      end_ = choice_entry_end(data, start, u0)
      invalid = (end_ == i0)
      if invalid
        none = nil
        return none
      end
      tag = data.getbyte(start)
      wrong_tag = (tag != u3)
      if wrong_tag
        none = nil
        return none
      end
      value_start = (start + i5)
      value = data.byteslice(value_start, end_ - value_start).dup
      some = value.dup
      return some
    end

    def deserialize_string_choice(data, start)
      i0 = 0
      i5 = 5
      u0 = 0
      u4 = 4
      end_ = choice_entry_end(data, start, u0)
      invalid = (end_ == i0)
      if invalid
        none = nil
        return none
      end
      tag = data.getbyte(start)
      wrong_tag = (tag != u4)
      if wrong_tag
        none = nil
        return none
      end
      value_start = (start + i5)
      value = data.byteslice(value_start, end_ - value_start).dup
      some = value.dup
      return some
    end

    def failure_use_compressed(compressed_n, raw_n)
      max = max_decompressed_len()
      shorter = (compressed_n < raw_n)
      fits = (raw_n <= max)
      use_ = (shorter && fits)
      return use_
    end

    def raw_failure_encode(serialized_choices)
      raw_payload = String.new(encoding: Encoding::BINARY)
      prefix_raw = 0
      prefix_zlib = 1
      raw_payload << (prefix_raw & 0xff)
      raw_prefixed = append_bytes(raw_payload, serialized_choices)
      compressed = zlib_compress(serialized_choices)
      compressed_len = compressed.bytesize
      compressed_n = (compressed_len & MASK)
      raw_len = serialized_choices.bytesize
      raw_n = (raw_len & MASK)
      use_compressed = failure_use_compressed(compressed_n, raw_n)
      chosen = raw_prefixed.dup
      if use_compressed
        zlib_payload = String.new(encoding: Encoding::BINARY)
        zlib_payload << (prefix_zlib & 0xff)
        chosen = append_bytes(zlib_payload, compressed)
      end
      blob = base64_encode(chosen)
      return blob
    end

    def raw_failure_decode(blob)
      decoded = base64_decode(blob)
      present = !decoded.nil?
      missing = (!present)
      if missing
        none = nil
        return none
      end
      payload = decoded
      i0 = 0
      i1 = 1
      u0 = 0
      n = payload.bytesize
      empty = (n == i0)
      if empty
        none = nil
        return none
      end
      prefix = payload.getbyte(i0)
      u1_prefix = 1
      raw = (prefix == u0)
      compressed = (prefix == u1_prefix)
      known = (raw || compressed)
      unknown = (!known)
      if unknown
        none = nil
        return none
      end
      serialized = payload.byteslice(i1, n - i1).dup
      if compressed
        inflated = zlib_decompress(serialized)
        inflated_ok = !inflated.nil?
        inflate_failed = (!inflated_ok)
        if inflate_failed
          none = nil
          return none
        end
        serialized = inflated
      end
      valid = choice_stream_validate(serialized)
      invalid = (!valid)
      if invalid
        none = nil
        return none
      end
      some = serialized.dup
      return some
    end

    def alphabet_codepoint_allowed(codepoint)
      false_ = false
      true_ = true
      max = 1114111
      surrogate_low = 55296
      surrogate_high = 57343
      too_high = (codepoint > max)
      if too_high
        return false_
      end
      at_or_above_low = (codepoint >= surrogate_low)
      at_or_below_high = (codepoint <= surrogate_high)
      surrogate = (at_or_above_low && at_or_below_high)
      if surrogate
        return false_
      end
      return true_
    end

    def alphabet_interval_count(alphabet)
      u3 = 3
      length = alphabet.bytesize
      length_u64 = (length & MASK)
      count = (length_u64 >> u3)
      return count
    end

    def alphabet_interval_start(alphabet, interval)
      i8 = 8
      interval_i64 = u64_to_i64(interval)
      offset = (interval_i64 * i8)
      start = read_u32_le(alphabet, offset)
      return start
    end

    def alphabet_interval_end(alphabet, interval)
      i4 = 4
      i8 = 8
      interval_i64 = u64_to_i64(interval)
      base = (interval_i64 * i8)
      offset = (base + i4)
      end_ = read_u32_le(alphabet, offset)
      return end_
    end

    def alphabet_valid(alphabet)
      false_ = false
      true_ = true
      i0 = 0
      u0 = 0
      u1 = 1
      u3 = 3
      length = alphabet.bytesize
      empty = (length <= i0)
      if empty
        return false_
      end
      length_u64 = (length & MASK)
      count_u64 = (length_u64 >> u3)
      exact = ((count_u64 << u3) & MASK)
      ragged = (exact != length_u64)
      if ragged
        return false_
      end
      previous_end = u0
      interval = u0
      loop do
        done = (interval >= count_u64)
        if done
          break
        end
        start = alphabet_interval_start(alphabet, interval)
        end_ = alphabet_interval_end(alphabet, interval)
        descending = (start > end_)
        if descending
          return false_
        end
        start_ok = alphabet_codepoint_allowed(start)
        start_bad = (!start_ok)
        if start_bad
          return false_
        end
        end_ok = alphabet_codepoint_allowed(end_)
        end_bad = (!end_ok)
        if end_bad
          return false_
        end
        surrogate_low = 55296
        surrogate_high = 57343
        spans_below = (start <= surrogate_high)
        spans_above = (end_ >= surrogate_low)
        straddles = (spans_below && spans_above)
        if straddles
          return false_
        end
        later = (interval > u0)
        if later
          needed = ((previous_end + u1) & MASK)
          touching = (start <= needed)
          if touching
            return false_
          end
        end
        previous_end = end_
        interval = ((interval + u1) & MASK)
      end
      return true_
    end

    def alphabet_size(alphabet)
      u0 = 0
      u1 = 1
      count = alphabet_interval_count(alphabet)
      size = u0
      interval = u0
      loop do
        done = (interval >= count)
        if done
          break
        end
        start = alphabet_interval_start(alphabet, interval)
        end_ = alphabet_interval_end(alphabet, interval)
        span = ((end_ - start) & MASK)
        members = ((span + u1) & MASK)
        size = ((size + members) & MASK)
        interval = ((interval + u1) & MASK)
      end
      return size
    end

    def alphabet_index_of(alphabet, codepoint)
      u0 = 0
      u1 = 1
      count = alphabet_interval_count(alphabet)
      offset = u0
      interval = u0
      loop do
        done = (interval >= count)
        if done
          break
        end
        start = alphabet_interval_start(alphabet, interval)
        end_ = alphabet_interval_end(alphabet, interval)
        at_or_above = (codepoint >= start)
        at_or_below = (codepoint <= end_)
        inside = (at_or_above && at_or_below)
        if inside
          within = ((codepoint - start) & MASK)
          index = ((offset + within) & MASK)
          found = index
          return found
        end
        span = ((end_ - start) & MASK)
        members = ((span + u1) & MASK)
        offset = ((offset + members) & MASK)
        interval = ((interval + u1) & MASK)
      end
      missing = nil
      return missing
    end

    def alphabet_codepoint_at(alphabet, index)
      u0 = 0
      u1 = 1
      count = alphabet_interval_count(alphabet)
      remaining = index
      interval = u0
      loop do
        done = (interval >= count)
        if done
          break
        end
        start = alphabet_interval_start(alphabet, interval)
        end_ = alphabet_interval_end(alphabet, interval)
        span = ((end_ - start) & MASK)
        members = ((span + u1) & MASK)
        inside = (remaining < members)
        if inside
          codepoint = ((start + remaining) & MASK)
          found = codepoint
          return found
        end
        remaining = ((remaining - members) & MASK)
        interval = ((interval + u1) & MASK)
      end
      missing = nil
      return missing
    end

    def alphabet_contains(alphabet, codepoint)
      index = alphabet_index_of(alphabet, codepoint)
      present = !index.nil?
      return present
    end

    def alphabet_index_above(alphabet, codepoint)
      u0 = 0
      u1 = 1
      count = alphabet_interval_count(alphabet)
      below = u0
      interval = u0
      loop do
        done = (interval >= count)
        if done
          break
        end
        start = alphabet_interval_start(alphabet, interval)
        end_ = alphabet_interval_end(alphabet, interval)
        before_interval = (codepoint <= start)
        if before_interval
          return below
        end
        inside = (codepoint <= end_)
        if inside
          within = ((codepoint - start) & MASK)
          index = ((below + within) & MASK)
          return index
        end
        span = ((end_ - start) & MASK)
        members = ((span + u1) & MASK)
        below = ((below + members) & MASK)
        interval = ((interval + u1) & MASK)
      end
      return below
    end

    def alphabet_shrink_pivot(alphabet)
      zero = 48
      pivot = alphabet_index_above(alphabet, zero)
      return pivot
    end

    def alphabet_shrink_last(alphabet)
      u0 = 0
      u1 = 1
      upper_z = 90
      found = alphabet_index_of(alphabet, upper_z)
      present = !found.nil?
      if present
        index = found
        return index
      end
      pivot = alphabet_shrink_pivot(alphabet)
      at_front = (pivot == u0)
      if at_front
        return u0
      end
      last = ((pivot - u1) & MASK)
      return last
    end

    def alphabet_shrink_promoted(alphabet)
      u0 = 0
      u1 = 1
      pivot = alphabet_shrink_pivot(alphabet)
      last = alphabet_shrink_last(alphabet)
      empty = (last < pivot)
      if empty
        return u0
      end
      span = ((last - pivot) & MASK)
      promoted = ((span + u1) & MASK)
      return promoted
    end

    def alphabet_shrink_index(alphabet, rank)
      size = alphabet_size(alphabet)
      past_end = (rank >= size)
      if past_end
        return rank
      end
      pivot = alphabet_shrink_pivot(alphabet)
      last = alphabet_shrink_last(alphabet)
      promoted = alphabet_shrink_promoted(alphabet)
      in_promoted = (rank < promoted)
      if in_promoted
        index = ((pivot + rank) & MASK)
        return index
      end
      displaced = (rank <= last)
      if displaced
        index = ((rank - promoted) & MASK)
        return index
      end
      return rank
    end

    def alphabet_shrink_rank(alphabet, index)
      size = alphabet_size(alphabet)
      past_end = (index >= size)
      if past_end
        return index
      end
      pivot = alphabet_shrink_pivot(alphabet)
      last = alphabet_shrink_last(alphabet)
      promoted = alphabet_shrink_promoted(alphabet)
      at_or_above = (index >= pivot)
      at_or_below = (index <= last)
      in_promoted = (at_or_above && at_or_below)
      if in_promoted
        rank = ((index - pivot) & MASK)
        return rank
      end
      below = (index < pivot)
      if below
        rank = ((index + promoted) & MASK)
        return rank
      end
      return index
    end

    def alphabet_shrink_codepoint(alphabet, rank)
      index = alphabet_shrink_index(alphabet, rank)
      codepoint = alphabet_codepoint_at(alphabet, index)
      return codepoint
    end

    def alphabet_range(min_codepoint, max_codepoint)
      out = String.new(encoding: Encoding::BINARY)
      max = 1114111
      surrogate_below = 55295
      surrogate_above = 57344
      low = min_codepoint
      high = max_codepoint
      over = (high > max)
      if over
        high = max
      end
      empty = (low > high)
      if empty
        return out
      end
      starts_below = (low <= surrogate_below)
      if starts_below
        first_end = high
        clip = (first_end > surrogate_below)
        if clip
          first_end = surrogate_below
        end
        start_bytes = u32_to_le(low)
        end_bytes = u32_to_le(first_end)
        out = append_bytes(out, start_bytes)
        out = append_bytes(out, end_bytes)
      end
      ends_above = (high >= surrogate_above)
      if ends_above
        second_start = low
        lift = (second_start < surrogate_above)
        if lift
          second_start = surrogate_above
        end
        start_bytes = u32_to_le(second_start)
        end_bytes = u32_to_le(high)
        out = append_bytes(out, start_bytes)
        out = append_bytes(out, end_bytes)
      end
      return out
    end

    def alphabet_insert(alphabet, codepoint)
      u0 = 0
      u1 = 1
      count = alphabet_interval_count(alphabet)
      out = String.new(encoding: Encoding::BINARY)
      allowed = alphabet_codepoint_allowed(codepoint)
      rejected = (!allowed)
      if rejected
        unchanged = append_bytes(out, alphabet)
        return unchanged
      end
      pending_start = codepoint
      pending_end = codepoint
      placed = false
      interval = u0
      loop do
        done = (interval >= count)
        if done
          break
        end
        start = alphabet_interval_start(alphabet, interval)
        end_ = alphabet_interval_end(alphabet, interval)
        gap_start = ((end_ + u1) & MASK)
        strictly_below = (gap_start < pending_start)
        if strictly_below
          start_bytes = u32_to_le(start)
          end_bytes = u32_to_le(end_)
          out = append_bytes(out, start_bytes)
          out = append_bytes(out, end_bytes)
        end
        touches_below = (!strictly_below)
        if touches_below
          gap_end = ((pending_end + u1) & MASK)
          strictly_above = (start > gap_end)
          if strictly_above
            not_yet = (!placed)
            if not_yet
              pending_start_bytes = u32_to_le(pending_start)
              pending_end_bytes = u32_to_le(pending_end)
              out = append_bytes(out, pending_start_bytes)
              out = append_bytes(out, pending_end_bytes)
              placed = true
            end
            start_bytes = u32_to_le(start)
            end_bytes = u32_to_le(end_)
            out = append_bytes(out, start_bytes)
            out = append_bytes(out, end_bytes)
          end
          overlaps = (!strictly_above)
          if overlaps
            lower = (start < pending_start)
            if lower
              pending_start = start
            end
            higher = (end_ > pending_end)
            if higher
              pending_end = end_
            end
          end
        end
        interval = ((interval + u1) & MASK)
      end
      unplaced = (!placed)
      if unplaced
        pending_start_bytes = u32_to_le(pending_start)
        pending_end_bytes = u32_to_le(pending_end)
        out = append_bytes(out, pending_start_bytes)
        out = append_bytes(out, pending_end_bytes)
      end
      return out
    end

    def string_length(value)
      u2 = 2
      length = value.bytesize
      length_u64 = (length & MASK)
      count_u64 = (length_u64 >> u2)
      count = u64_to_i64(count_u64)
      return count
    end

    def string_codepoint_at(value, position)
      i4 = 4
      offset = (position * i4)
      codepoint = read_u32_le(value, offset)
      return codepoint
    end

    def string_validate(alphabet, min_size, max_size, value)
      false_ = false
      true_ = true
      i0 = 0
      i1 = 1
      i4 = 4
      length = value.bytesize
      count = string_length(value)
      exact = (count * i4)
      ragged = (exact != length)
      if ragged
        return false_
      end
      too_short = (count < min_size)
      if too_short
        return false_
      end
      too_long = (count > max_size)
      if too_long
        return false_
      end
      position = i0
      loop do
        done = (position >= count)
        if done
          break
        end
        codepoint = string_codepoint_at(value, position)
        member = alphabet_contains(alphabet, codepoint)
        outside = (!member)
        if outside
          return false_
        end
        position = (position + i1)
      end
      return true_
    end

    def string_simplest(alphabet, min_size)
      out = String.new(encoding: Encoding::BINARY)
      i0 = 0
      i1 = 1
      u0 = 0
      first = alphabet_shrink_codepoint(alphabet, u0)
      present = !first.nil?
      empty_alphabet = (!present)
      if empty_alphabet
        return out
      end
      codepoint = first
      packed_ = u32_to_le(codepoint)
      position = i0
      loop do
        done = (position >= min_size)
        if done
          break
        end
        out = append_bytes(out, packed_)
        position = (position + i1)
      end
      return out
    end

    def string_unit(alphabet, min_size, max_size)
      out = String.new(encoding: Encoding::BINARY)
      i0 = 0
      i1 = 1
      u0 = 0
      u1 = 1
      first = alphabet_shrink_codepoint(alphabet, u0)
      present = !first.nil?
      empty_alphabet = (!present)
      if empty_alphabet
        return out
      end
      lowest = first
      next_ = alphabet_shrink_codepoint(alphabet, u1)
      has_next = !next_.nil?
      stepped = lowest
      if has_next
        second = next_
        stepped = second
      end
      lowest_packed = u32_to_le(lowest)
      stepped_packed = u32_to_le(stepped)
      has_minimum = (min_size > i0)
      if has_minimum
        last = (min_size - i1)
        position = i0
        loop do
          done = (position >= min_size)
          if done
            break
          end
          is_last = (position == last)
          if is_last
            out = append_bytes(out, stepped_packed)
          end
          is_earlier = (!is_last)
          if is_earlier
            out = append_bytes(out, lowest_packed)
          end
          position = (position + i1)
        end
        return out
      end
      has_room = (max_size > i0)
      if has_room
        out = append_bytes(out, stepped_packed)
      end
      return out
    end

    def string_duplicate_rank(alphabet, value)
      i0 = 0
      i1 = 1
      u0 = 0
      u1 = 1
      u2 = 2
      length = string_length(value)
      best = u0
      found = false
      at = i0
      loop do
        done = (at >= length)
        if done
          break
        end
        codepoint = string_codepoint_at(value, at)
        index = alphabet_index_of(alphabet, codepoint)
        present = !index.nil?
        if present
          index_value = index
          rank = alphabet_shrink_rank(alphabet, index_value)
          lowerable = (rank != u0)
          improves = (rank > best)
          not_found = (!found)
          better = (improves || not_found)
          worth_counting = (lowerable && better)
          if worth_counting
            seen = u0
            other = i0
            loop do
              counted = (other >= length)
              if counted
                break
              end
              other_codepoint = string_codepoint_at(value, other)
              other_index = alphabet_index_of(alphabet, other_codepoint)
              other_present = !other_index.nil?
              if other_present
                other_index_value = other_index
                other_rank = alphabet_shrink_rank(alphabet, other_index_value)
                same = (other_rank == rank)
                if same
                  seen = ((seen + u1) & MASK)
                end
              end
              other = (other + i1)
            end
            repeated = (seen >= u2)
            if repeated
              best = rank
              found = true
            end
          end
        end
        at = (at + i1)
      end
      missing = (!found)
      if missing
        none = nil
        return none
      end
      some = best
      return some
    end

    def string_replace_rank(alphabet, value, from_rank, to_rank)
      i0 = 0
      i1 = 1
      unchanged = (from_rank == to_rank)
      if unchanged
        none_same = nil
        return none_same
      end
      target = alphabet_shrink_codepoint(alphabet, to_rank)
      target_present = !target.nil?
      target_missing = (!target_present)
      if target_missing
        none_target = nil
        return none_target
      end
      target_codepoint = target
      length = string_length(value)
      out = String.new(encoding: Encoding::BINARY)
      at = i0
      loop do
        done = (at >= length)
        if done
          break
        end
        codepoint = string_codepoint_at(value, at)
        emitted = codepoint
        index = alphabet_index_of(alphabet, codepoint)
        present = !index.nil?
        if present
          index_value = index
          rank = alphabet_shrink_rank(alphabet, index_value)
          matches = (rank == from_rank)
          if matches
            emitted = target_codepoint
          end
        end
        packed_ = u32_to_le(emitted)
        out = append_bytes(out, packed_)
        at = (at + i1)
      end
      some = out.dup
      return some
    end

    def string_drop_character(value, min_size, position)
      i0 = 0
      i1 = 1
      length = string_length(value)
      at_minimum = (length <= min_size)
      if at_minimum
        none_minimum = nil
        return none_minimum
      end
      before_start = (position < i0)
      if before_start
        none_before = nil
        return none_before
      end
      past_end = (position >= length)
      if past_end
        none_past = nil
        return none_past
      end
      out = String.new(encoding: Encoding::BINARY)
      at = i0
      loop do
        done = (at >= length)
        if done
          break
        end
        dropped = (at == position)
        kept = (!dropped)
        if kept
          codepoint = string_codepoint_at(value, at)
          packed_ = u32_to_le(codepoint)
          out = append_bytes(out, packed_)
        end
        at = (at + i1)
      end
      some = out.dup
      return some
    end

    def string_to_index(alphabet, min_size, value)
      i0 = 0
      i1 = 1
      u0 = 0
      size = alphabet_size(alphabet)
      base = u64_to_bigint_le(size)
      count = string_length(value)
      offset = bigint_zero()
      length = min_size
      loop do
        done = (length >= count)
        if done
          break
        end
        exponent = (length & MASK)
        bucket = positive_pow_le(base, exponent)
        offset = signed_add_le(offset, bucket)
        length = (length + i1)
      end
      position = bigint_zero()
      pos = i0
      loop do
        done = (pos >= count)
        if done
          break
        end
        codepoint = string_codepoint_at(value, pos)
        found = alphabet_index_of(alphabet, codepoint)
        present = !found.nil?
        rank = u0
        if present
          alphabet_index = found
          rank = alphabet_shrink_rank(alphabet, alphabet_index)
        end
        digit = u64_to_bigint_le(rank)
        shifted = signed_mul_le(position, base)
        position = signed_add_le(shifted, digit)
        pos = (pos + i1)
      end
      index = signed_add_le(offset, position)
      return index
    end

    def string_max_index(alphabet, min_size, max_size)
      i0 = 0
      i1 = 1
      u0 = 0
      u1 = 1
      size = alphabet_size(alphabet)
      no_members = (size == u0)
      if no_members
        zero = bigint_zero()
        return zero
      end
      top_rank = ((size - u1) & MASK)
      top = alphabet_shrink_codepoint(alphabet, top_rank)
      present = !top.nil?
      missing = (!present)
      if missing
        zero = bigint_zero()
        return zero
      end
      codepoint = top
      packed_ = u32_to_le(codepoint)
      last = String.new(encoding: Encoding::BINARY)
      position = i0
      loop do
        done = (position >= max_size)
        if done
          break
        end
        last = append_bytes(last, packed_)
        position = (position + i1)
      end
      index = string_to_index(alphabet, min_size, last)
      return index
    end

    def string_from_index(alphabet, min_size, max_size, index_raw)
      i0 = 0
      i1 = 1
      u0 = 0
      size = alphabet_size(alphabet)
      no_members = (size == u0)
      if no_members
        none = nil
        return none
      end
      base = u64_to_bigint_le(size)
      remaining = signed_abs_le(index_raw)
      length = min_size
      loop do
        past_end = (length > max_size)
        if past_end
          break
        end
        exponent = (length & MASK)
        bucket = positive_pow_le(base, exponent)
        bucket_cmp = signed_compare_le(remaining, bucket)
        inside_bucket = (bucket_cmp < i0)
        if inside_bucket
          out = String.new(encoding: Encoding::BINARY)
          empty = (length == i0)
          if empty
            some_empty = out.dup
            return some_empty
          end
          power = (length - i1)
          power_u64 = (power & MASK)
          divisor = positive_pow_le(base, power_u64)
          pos = i0
          loop do
            done = (pos >= length)
            if done
              break
            end
            digit = positive_div_le_nonzero(remaining, divisor)
            digit_u64 = bigint_to_u64_le(digit)
            digit_fits = !digit_u64.nil?
            rank = u0
            if digit_fits
              rank = digit_u64
            end
            found = alphabet_shrink_codepoint(alphabet, rank)
            present = !found.nil?
            codepoint = u0
            if present
              codepoint = found
            end
            packed_ = u32_to_le(codepoint)
            out = append_bytes(out, packed_)
            remaining = positive_rem_le_nonzero(remaining, divisor)
            divisor = positive_div_le_nonzero(divisor, base)
            pos = (pos + i1)
          end
          some = out.dup
          return some
        end
        remaining = signed_sub_le(remaining, bucket)
        length = (length + i1)
      end
      none = nil
      return none
    end

    def choice_delete_range(data, start_index, end_index)
      i4 = 4
      u0 = 0
      u1 = 1
      stream_valid = choice_stream_validate(data)
      stream_invalid = (!stream_valid)
      if stream_invalid
        none = nil
        return none
      end
      count = choice_stream_count(data)
      ordered = (start_index <= end_index)
      end_valid = (end_index <= count)
      bounds_valid = (ordered && end_valid)
      bounds_invalid = (!bounds_valid)
      if bounds_invalid
        none = nil
        return none
      end
      position = i4
      index = u0
      start_offset = i4
      loop do
        done = (index >= end_index)
        if done
          break
        end
        at_start = (index == start_index)
        if at_start
          start_offset = position
        end
        next_ = choice_entry_end(data, position, u0)
        position = next_
        index = ((index + u1) & MASK)
      end
      empty_range = (start_index == end_index)
      if empty_range
        start_offset = position
      end
      end_offset = position
      data_end = data.bytesize
      before = data.byteslice(i4, start_offset - i4).dup
      after = data.byteslice(end_offset, data_end - end_offset).dup
      removed = ((end_index - start_index) & MASK)
      new_count = ((count - removed) & MASK)
      header = choice_list_header(new_count)
      with_before = append_bytes(header, before)
      out = append_bytes(with_before, after)
      some = out.dup
      return some
    end

    def choice_swap_ranges(data, a_start, a_end, b_start, b_end)
      i4 = 4
      u0 = 0
      u1 = 1
      stream_valid = choice_stream_validate(data)
      stream_invalid = (!stream_valid)
      if stream_invalid
        none_stream = nil
        return none_stream
      end
      count = choice_stream_count(data)
      a_ordered = (a_start <= a_end)
      disjoint = (a_end <= b_start)
      b_ordered = (b_start <= b_end)
      in_range = (b_end <= count)
      front_ok = (a_ordered && disjoint)
      back_ok = (b_ordered && in_range)
      bounds_valid = (front_ok && back_ok)
      bounds_invalid = (!bounds_valid)
      if bounds_invalid
        none_bounds = nil
        return none_bounds
      end
      position = i4
      index = u0
      a_start_offset = i4
      a_end_offset = i4
      b_start_offset = i4
      loop do
        done = (index >= b_end)
        if done
          break
        end
        at_a_start = (index == a_start)
        if at_a_start
          a_start_offset = position
        end
        at_a_end = (index == a_end)
        if at_a_end
          a_end_offset = position
        end
        at_b_start = (index == b_start)
        if at_b_start
          b_start_offset = position
        end
        next_ = choice_entry_end(data, position, u0)
        position = next_
        index = ((index + u1) & MASK)
      end
      a_start_at_end = (a_start == b_end)
      if a_start_at_end
        a_start_offset = position
      end
      a_end_at_end = (a_end == b_end)
      if a_end_at_end
        a_end_offset = position
      end
      b_start_at_end = (b_start == b_end)
      if b_start_at_end
        b_start_offset = position
      end
      b_end_offset = position
      data_end = data.bytesize
      before = data.byteslice(i4, a_start_offset - i4).dup
      first = data.byteslice(a_start_offset, a_end_offset - a_start_offset).dup
      middle = data.byteslice(a_end_offset, b_start_offset - a_end_offset).dup
      second = data.byteslice(b_start_offset, b_end_offset - b_start_offset).dup
      after = data.byteslice(b_end_offset, data_end - b_end_offset).dup
      header = choice_list_header(count)
      with_before = append_bytes(header, before)
      with_second = append_bytes(with_before, second)
      with_middle = append_bytes(with_second, middle)
      with_first = append_bytes(with_middle, first)
      out = append_bytes(with_first, after)
      some = out.dup
      return some
    end

    def choice_duplicate_ranges(data, a_start, a_end, b_start, b_end, use_a)
      i4 = 4
      u0 = 0
      u1 = 1
      u2 = 2
      stream_valid = choice_stream_validate(data)
      stream_invalid = (!stream_valid)
      if stream_invalid
        none_stream = nil
        return none_stream
      end
      count = choice_stream_count(data)
      a_ordered = (a_start < a_end)
      disjoint = (a_end <= b_start)
      b_ordered = (b_start < b_end)
      in_range = (b_end <= count)
      front_ok = (a_ordered && disjoint)
      back_ok = (b_ordered && in_range)
      bounds_valid = (front_ok && back_ok)
      bounds_invalid = (!bounds_valid)
      if bounds_invalid
        none_bounds = nil
        return none_bounds
      end
      position = i4
      index = u0
      a_start_offset = i4
      a_end_offset = i4
      b_start_offset = i4
      loop do
        done = (index >= b_end)
        if done
          break
        end
        at_a_start = (index == a_start)
        if at_a_start
          a_start_offset = position
        end
        at_a_end = (index == a_end)
        if at_a_end
          a_end_offset = position
        end
        at_b_start = (index == b_start)
        if at_b_start
          b_start_offset = position
        end
        next_ = choice_entry_end(data, position, u0)
        position = next_
        index = ((index + u1) & MASK)
      end
      b_end_offset = position
      data_end = data.bytesize
      before = data.byteslice(i4, a_start_offset - i4).dup
      first = data.byteslice(a_start_offset, a_end_offset - a_start_offset).dup
      middle = data.byteslice(a_end_offset, b_start_offset - a_end_offset).dup
      second = data.byteslice(b_start_offset, b_end_offset - b_start_offset).dup
      after = data.byteslice(b_end_offset, data_end - b_end_offset).dup
      donor = second.dup
      donor_count = ((b_end - b_start) & MASK)
      if use_a
        donor = first.dup
        donor_count = ((a_end - a_start) & MASK)
      end
      a_count = ((a_end - a_start) & MASK)
      b_count = ((b_end - b_start) & MASK)
      removed = ((a_count + b_count) & MASK)
      base_count = ((count - removed) & MASK)
      twice_donor = ((donor_count * u2) & MASK)
      new_count = ((base_count + twice_donor) & MASK)
      header = choice_list_header(new_count)
      with_before = append_bytes(header, before)
      with_first = append_bytes(with_before, donor)
      with_middle = append_bytes(with_first, middle)
      with_second = append_bytes(with_middle, donor)
      out = append_bytes(with_second, after)
      some = out.dup
      return some
    end

    def choice_duplicate_nested_prefix(data, outer_start, outer_end, inner_start, inner_end)
      i4 = 4
      u0 = 0
      u1 = 1
      stream_valid = choice_stream_validate(data)
      stream_invalid = (!stream_valid)
      if stream_invalid
        none_stream = nil
        return none_stream
      end
      count = choice_stream_count(data)
      outer_nonempty = (outer_start < outer_end)
      inner_nonempty = (inner_start < inner_end)
      starts_inside = (outer_start <= inner_start)
      ends_inside = (inner_end <= outer_end)
      in_range = (outer_end <= count)
      nonempty = (outer_nonempty && inner_nonempty)
      contained = (starts_inside && ends_inside)
      shape_valid = (nonempty && contained)
      bounds_valid = (shape_valid && in_range)
      bounds_invalid = (!bounds_valid)
      if bounds_invalid
        none_bounds = nil
        return none_bounds
      end
      position = i4
      index = u0
      outer_offset = i4
      loop do
        done = (index >= inner_start)
        if done
          break
        end
        at_outer = (index == outer_start)
        if at_outer
          outer_offset = position
        end
        next_ = choice_entry_end(data, position, u0)
        position = next_
        index = ((index + u1) & MASK)
      end
      same_start = (outer_start == inner_start)
      if same_start
        outer_offset = position
      end
      inner_offset = position
      data_end = data.bytesize
      before_inner = data.byteslice(i4, inner_offset - i4).dup
      from_outer = data.byteslice(outer_offset, data_end - outer_offset).dup
      prefix_count = ((inner_start - outer_start) & MASK)
      new_count = ((count + prefix_count) & MASK)
      header = choice_list_header(new_count)
      with_before = append_bytes(header, before_inner)
      out = append_bytes(with_before, from_outer)
      some = out.dup
      return some
    end

    def choice_mutate_ranges(data, a_start, a_end, b_start, b_end, use_a)
      a_before_b = (a_start <= b_start)
      b_ends_in_a = (b_end <= a_end)
      a_contains_b = (a_before_b && b_ends_in_a)
      if a_contains_b
        nested_a = choice_duplicate_nested_prefix(data, a_start, a_end, b_start, b_end)
        return nested_a
      end
      b_before_a = (b_start <= a_start)
      a_ends_in_b = (a_end <= b_end)
      b_contains_a = (b_before_a && a_ends_in_b)
      if b_contains_a
        nested_b = choice_duplicate_nested_prefix(data, b_start, b_end, a_start, a_end)
        return nested_b
      end
      if a_before_b
        duplicate_ab = choice_duplicate_ranges(data, a_start, a_end, b_start, b_end, use_a)
        return duplicate_ab
      end
      use_b = (!use_a)
      duplicate_ba = choice_duplicate_ranges(data, b_start, b_end, a_start, a_end, use_b)
      return duplicate_ba
    end

    def clone_inner_stream(data, offset)
      i0 = 0
      i1 = 1
      u0 = 0
      u5 = 5
      n = data.bytesize
      at = u64_to_i64(offset)
      past_end = (at >= n)
      if past_end
        none = nil
        return none
      end
      tag = data.getbyte(at)
      not_clone = (tag != u5)
      if not_clone
        none = nil
        return none
      end
      end_ = choice_entry_end(data, at, u0)
      malformed = (end_ == i0)
      if malformed
        none = nil
        return none
      end
      payload_start = (at + i1)
      inner = data.byteslice(payload_start, end_ - payload_start).dup
      some = inner.dup
      return some
    end

    def clone_replace_inner(data, offset, inner)
      i0 = 0
      i1 = 1
      u0 = 0
      u5 = 5
      n = data.bytesize
      at = u64_to_i64(offset)
      past_end = (at >= n)
      if past_end
        none = nil
        return none
      end
      tag = data.getbyte(at)
      not_clone = (tag != u5)
      if not_clone
        none = nil
        return none
      end
      inner_valid = choice_stream_validate(inner)
      inner_invalid = (!inner_valid)
      if inner_invalid
        none = nil
        return none
      end
      end_ = choice_entry_end(data, at, u0)
      malformed = (end_ == i0)
      if malformed
        none = nil
        return none
      end
      prefix_end = (at + i1)
      head = data.byteslice(i0, prefix_end - i0).dup
      tail = data.byteslice(end_, n - end_).dup
      out = String.new(encoding: Encoding::BINARY)
      with_head = append_bytes(out, head)
      with_inner = append_bytes(with_head, inner)
      rebuilt = append_bytes(with_inner, tail)
      some = rebuilt.dup
      return some
    end

    def choice_offset_at(data, index)
      i0 = 0
      i4 = 4
      u0 = 0
      u1 = 1
      stream_valid = choice_stream_validate(data)
      stream_invalid = (!stream_valid)
      if stream_invalid
        none = nil
        return none
      end
      count = choice_stream_count(data)
      past_end = (index >= count)
      if past_end
        none = nil
        return none
      end
      position = i4
      seen = u0
      loop do
        found = (seen >= index)
        if found
          break
        end
        next_ = choice_entry_end(data, position, u0)
        malformed = (next_ == i0)
        if malformed
          none = nil
          return none
        end
        position = next_
        seen = ((seen + u1) & MASK)
      end
      offset = (position & MASK)
      some = offset
      return some
    end

    def integer_boundary_eligible(candidate, min_value, max_value)
      above_min = (candidate >= min_value)
      below_max = (candidate <= max_value)
      in_range = (above_min && below_max)
      is_min = (candidate == min_value)
      is_max = (candidate == max_value)
      is_boundary = (is_min || is_max)
      not_boundary = (!is_boundary)
      eligible = (in_range && not_boundary)
      return eligible
    end

    def integer_boundary_candidate(min_value, max_value, ordinal)
      i0 = 0
      i1 = 1
      i2 = 2
      u0 = 0
      u1 = 1
      u63 = 63
      want_min = (ordinal == u0)
      if want_min
        some_min = min_value
        return some_min
      end
      seen = u1
      same_bounds = (min_value == max_value)
      distinct_bounds = (!same_bounds)
      if distinct_bounds
        want_max = (ordinal == seen)
        if want_max
          some_max = max_value
          return some_max
        end
        seen = ((seen + u1) & MASK)
      end
      zero_eligible = integer_boundary_eligible(i0, min_value, max_value)
      if zero_eligible
        want_zero = (ordinal == seen)
        if want_zero
          some_zero = i0
          return some_zero
        end
        seen = ((seen + u1) & MASK)
      end
      power = i1
      iteration = u0
      loop do
        done = (iteration >= u63)
        if done
          break
        end
        positive_eligible = integer_boundary_eligible(power, min_value, max_value)
        if positive_eligible
          want_positive = (ordinal == seen)
          if want_positive
            some_positive = power
            return some_positive
          end
          seen = ((seen + u1) & MASK)
        end
        negative = (i0 - power)
        negative_eligible = integer_boundary_eligible(negative, min_value, max_value)
        if negative_eligible
          want_negative = (ordinal == seen)
          if want_negative
            some_negative = negative
            return some_negative
          end
          seen = ((seen + u1) & MASK)
        end
        iteration = ((iteration + u1) & MASK)
        has_more = (iteration < u63)
        if has_more
          power = (power * i2)
        end
      end
      none = nil
      return none
    end

    def integer_swarm_is_wide(min_value, max_value)
      min_bits = (min_value & MASK)
      max_bits = (max_value & MASK)
      width = ((max_bits - min_bits) & MASK)
      u256 = 256
      wide = (width >= u256)
      return wide
    end

    def integer_swarm_endpoint_permille(entropy)
      mask = 255
      slot = (entropy & mask)
      u10 = 10
      u41 = 41
      u51 = 51
      u700 = 700
      u20 = 20
      u3 = 3
      endpoint_heavy = (slot < u10)
      if endpoint_heavy
        return u700
      end
      interesting_heavy = (slot < u41)
      if interesting_heavy
        return u20
      end
      diffuse_heavy = (slot < u51)
      if diffuse_heavy
        return u20
      end
      return u3
    end

    def integer_swarm_interesting_permille(entropy)
      mask = 255
      slot = (entropy & mask)
      u10 = 10
      u41 = 41
      u51 = 51
      u100 = 100
      u700 = 700
      u80 = 80
      endpoint_heavy = (slot < u10)
      if endpoint_heavy
        return u100
      end
      interesting_heavy = (slot < u41)
      if interesting_heavy
        return u700
      end
      diffuse_heavy = (slot < u51)
      if diffuse_heavy
        return u100
      end
      return u80
    end

    def integer_swarm_diffuse_permille(entropy)
      mask = 255
      slot = (entropy & mask)
      u10 = 10
      u41 = 41
      u51 = 51
      u50 = 50
      u80 = 80
      u700 = 700
      u17 = 17
      endpoint_heavy = (slot < u10)
      if endpoint_heavy
        return u50
      end
      interesting_heavy = (slot < u41)
      if interesting_heavy
        return u80
      end
      diffuse_heavy = (slot < u51)
      if diffuse_heavy
        return u700
      end
      return u17
    end

    def integer_swarm_category(entropy, roll)
      u0 = 0
      u1 = 1
      u2 = 2
      u3 = 3
      endpoint = integer_swarm_endpoint_permille(entropy)
      in_endpoint = (roll < endpoint)
      if in_endpoint
        return u0
      end
      interesting = integer_swarm_interesting_permille(entropy)
      after_interesting = ((endpoint + interesting) & MASK)
      in_interesting = (roll < after_interesting)
      if in_interesting
        return u1
      end
      diffuse = integer_swarm_diffuse_permille(entropy)
      after_diffuse = ((after_interesting + diffuse) & MASK)
      in_diffuse = (roll < after_diffuse)
      if in_diffuse
        return u2
      end
      return u3
    end

    def integer_swarm_endpoint_candidate(min_value, max_value, ordinal)
      u0 = 0
      u1 = 1
      u2 = 2
      u3 = 3
      i1 = 1
      is_min = (ordinal == u0)
      if is_min
        value = min_value
        return value
      end
      is_max = (ordinal == u1)
      if is_max
        value = max_value
        return value
      end
      is_min_neighbor = (ordinal == u2)
      if is_min_neighbor
        neighbor = (min_value + i1)
        value = neighbor
        return value
      end
      is_max_neighbor = (ordinal == u3)
      if is_max_neighbor
        neighbor = (max_value - i1)
        value = neighbor
        return value
      end
      none = nil
      return none
    end

    def integer_swarm_diffuse_count()
      count = 12
      return count
    end

    def integer_swarm_diffuse_if_in_range(candidate, min_value, max_value)
      above_min = (candidate >= min_value)
      below_max = (candidate <= max_value)
      eligible = (above_min && below_max)
      if eligible
        value = candidate
        return value
      end
      none = nil
      return none
    end

    def integer_swarm_diffuse_candidate(min_value, max_value, ordinal)
      u0 = 0
      u1 = 1
      u2 = 2
      u3 = 3
      u4 = 4
      u5 = 5
      u6 = 6
      u7 = 7
      u8 = 8
      u9 = 9
      u10 = 10
      u11 = 11
      i0 = 0
      match_ = (ordinal == u0)
      if match_
        candidate = 32767
        value = integer_swarm_diffuse_if_in_range(candidate, min_value, max_value)
        return value
      end
      match_ = (ordinal == u1)
      if match_
        m32768 = 32768
        candidate = (i0 - m32768)
        value = integer_swarm_diffuse_if_in_range(candidate, min_value, max_value)
        return value
      end
      match_ = (ordinal == u2)
      if match_
        candidate = 2147483647
        value = integer_swarm_diffuse_if_in_range(candidate, min_value, max_value)
        return value
      end
      match_ = (ordinal == u3)
      if match_
        m2147483648 = 2147483648
        candidate = (i0 - m2147483648)
        value = integer_swarm_diffuse_if_in_range(candidate, min_value, max_value)
        return value
      end
      match_ = (ordinal == u4)
      if match_
        candidate = 1000000
        value = integer_swarm_diffuse_if_in_range(candidate, min_value, max_value)
        return value
      end
      match_ = (ordinal == u5)
      if match_
        m1000000 = 1000000
        candidate = (i0 - m1000000)
        value = integer_swarm_diffuse_if_in_range(candidate, min_value, max_value)
        return value
      end
      match_ = (ordinal == u6)
      if match_
        candidate = 1000000000
        value = integer_swarm_diffuse_if_in_range(candidate, min_value, max_value)
        return value
      end
      match_ = (ordinal == u7)
      if match_
        m1000000000 = 1000000000
        candidate = (i0 - m1000000000)
        value = integer_swarm_diffuse_if_in_range(candidate, min_value, max_value)
        return value
      end
      match_ = (ordinal == u8)
      if match_
        candidate = 6148914691236517205
        value = integer_swarm_diffuse_if_in_range(candidate, min_value, max_value)
        return value
      end
      match_ = (ordinal == u9)
      if match_
        m6148914691236517205 = 6148914691236517205
        candidate = (i0 - m6148914691236517205)
        value = integer_swarm_diffuse_if_in_range(candidate, min_value, max_value)
        return value
      end
      match_ = (ordinal == u10)
      if match_
        candidate = 81985529216486895
        value = integer_swarm_diffuse_if_in_range(candidate, min_value, max_value)
        return value
      end
      match_ = (ordinal == u11)
      if match_
        m81985529216486895 = 81985529216486895
        candidate = (i0 - m81985529216486895)
        value = integer_swarm_diffuse_if_in_range(candidate, min_value, max_value)
        return value
      end
      none = nil
      return none
    end

    def integer_default_shrink_target(min_value, max_value)
      i0 = 0
      at_or_below = (min_value <= i0)
      at_or_above = (max_value >= i0)
      contains_zero = (at_or_below && at_or_above)
      if contains_zero
        return i0
      end
      return min_value
    end

    def text_widened_max(min_size)
      u15 = 15
      u16 = 16
      widened = ((min_size + u15) & MASK)
      below = (widened < u16)
      if below
        return u16
      end
      return widened
    end

    def integer_boundary_count(min_value, max_value)
      u0 = 0
      u1 = 1
      ordinal = u0
      loop do
        candidate = integer_boundary_candidate(min_value, max_value, ordinal)
        present = !candidate.nil?
        done = (!present)
        if done
          break
        end
        ordinal = ((ordinal + u1) & MASK)
      end
      return ordinal
    end

    def float_generation_spec_valid(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero)
      false_ = false
      min_nan = min_value.nan?
      if min_nan
        return false_
      end
      max_nan = max_value.nan?
      if max_nan
        return false_
      end
      smallest_nan = smallest_nonzero.nan?
      if smallest_nan
        return false_
      end
      zero = 0.to_f
      smallest_negative = (smallest_nonzero < zero)
      if smallest_negative
        return false_
      end
      ordered = sign_aware_lte(min_value, max_value)
      if ordered
        simplest = float_simplest(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero)
        usable = !simplest.nil?
        return usable
      end
      return false_
    end

    def float_entropy_below(word, count)
      mask = 4294967295
      u32 = 32
      word_low = (word & mask)
      word_high = (word >> u32)
      count_low = (count & mask)
      count_high = (count >> u32)
      low_low = ((word_low * count_low) & MASK)
      low_high = ((word_low * count_high) & MASK)
      high_low = ((word_high * count_low) & MASK)
      high_high = ((word_high * count_high) & MASK)
      carry = (low_low >> u32)
      low_high_low = (low_high & mask)
      high_low_low = (high_low & mask)
      middle = ((carry + low_high_low) & MASK)
      middle = ((middle + high_low_low) & MASK)
      low_high_high = (low_high >> u32)
      high_low_high = (high_low >> u32)
      middle_high = (middle >> u32)
      product = ((high_high + low_high_high) & MASK)
      product = ((product + high_low_high) & MASK)
      product = ((product + middle_high) & MASK)
      return product
    end

    def float_entropy_between(word, low, high)
      u1 = 1
      all = 18446744073709551615
      span = ((high - low) & MASK)
      full = (span == all)
      if full
        return word
      end
      count = ((span + u1) & MASK)
      offset = float_entropy_below(word, count)
      value = ((low + offset) & MASK)
      return value
    end

    def float_entropy_coin(word, bit)
      u1 = 1
      shifted = (word >> bit)
      low = (shifted & u1)
      set = (low == u1)
      return set
    end

    def float_entropy_unit(word)
      u11 = 11
      scale_bits = 4368491638549381120
      top = (word >> u11)
      integer = top.to_f
      scale = bits2f(scale_bits)
      unit = (integer * scale)
      return unit
    end

    def float_log_uniform_magnitude(low, high, exponent_word, mantissa_word)
      u0 = 0
      u52 = 52
      mantissa_mask = 4503599627370495
      low_bits = f2bits(low)
      high_bits = f2bits(high)
      low_exponent = (low_bits >> u52)
      high_exponent = (high_bits >> u52)
      exponent = float_entropy_between(exponent_word, low_exponent, high_exponent)
      mantissa_low = u0
      at_low = (exponent == low_exponent)
      if at_low
        mantissa_low = (low_bits & mantissa_mask)
      end
      mantissa_high = mantissa_mask
      at_high = (exponent == high_exponent)
      if at_high
        mantissa_high = (high_bits & mantissa_mask)
      end
      mantissa = float_entropy_between(mantissa_word, mantissa_low, mantissa_high)
      exponent_field = ((exponent << u52) & MASK)
      bits = (exponent_field | mantissa)
      magnitude = bits2f(bits)
      return magnitude
    end

    def float_bit_length(value)
      u0 = 0
      u1 = 1
      rest = value
      length = u0
      loop do
        done = (rest == u0)
        if done
          break
        end
        rest = (rest >> u1)
        length = ((length + u1) & MASK)
      end
      return length
    end

    def float_log_uniform_integer(low, high, binade_word, value_word)
      u0 = 0
      u1 = 1
      low_length = float_bit_length(low)
      high_length = float_bit_length(high)
      length = float_entropy_between(binade_word, low_length, high_length)
      first = u0
      last = u0
      nonzero = (length > u0)
      if nonzero
        shift = ((length - u1) & MASK)
        first = ((u1 << shift) & MASK)
        below_first = ((first - u1) & MASK)
        last = ((first + below_first) & MASK)
      end
      from_ = first
      low_above = (low > from_)
      if low_above
        from_ = low
      end
      to = last
      high_below = (high < to)
      if high_below
        to = high
      end
      value = float_entropy_between(value_word, from_, to)
      return value
    end

    def f64_next_up(value)
      u1 = 1
      zero = 0.to_f
      is_nan = value.nan?
      if is_nan
        return value
      end
      infinity = f64_infinity()
      at_top = (value == infinity)
      if at_top
        return value
      end
      is_zero = (value == zero)
      if is_zero
        smallest = bits2f(u1)
        return smallest
      end
      bits = f2bits(value)
      negative = (f2bits(value) >> 63) == 1
      if negative
        lower = ((bits - u1) & MASK)
        toward_zero = bits2f(lower)
        return toward_zero
      end
      higher = ((bits + u1) & MASK)
      away = bits2f(higher)
      return away
    end

    def f64_next_down(value)
      negated = f64_neg(value)
      up = f64_next_up(negated)
      down = f64_neg(up)
      return down
    end

    def f64_floor(value)
      one = 1.to_f
      ceiling = value.ceil.to_f
      integral = (ceiling == value)
      if integral
        return ceiling
      end
      floor = (ceiling - one)
      return floor
    end

    def float_category_is_point(category)
      u9 = 9
      u13 = 13
      from_nan = (category >= u9)
      to_zero = (category <= u13)
      point = (from_nan && to_zero)
      return point
    end

    def float_swarm_weight(entropy, category)
      u0 = 0
      u2 = 2
      u3 = 3
      u4 = 4
      u8 = 8
      u12 = 12
      u15 = 15
      u16 = 16
      u17 = 17
      u34 = 34
      u50 = 50
      u52 = 52
      u64 = 64
      u150 = 150
      u200 = 200
      u255 = 255
      u541 = 541
      u1000 = 1000
      out_of_range = (category > u16)
      if out_of_range
        return u0
      end
      is_default = (category == u16)
      point = float_category_is_point(category)
      slot = (entropy & u255)
      ordinary = (slot >= u64)
      if ordinary
        if is_default
          return u541
        end
        if point
          return u17
        end
        return u34
      end
      focus_field = (entropy >> u8)
      focus = (focus_field & u15)
      level_field = (entropy >> u12)
      level_step = (level_field & u3)
      level_rise = ((level_step * u150) & MASK)
      level = ((u200 + level_rise) & MASK)
      if is_default
        floor = u50
        focus_point = float_category_is_point(focus)
        if focus_point
          floor = u52
        end
        claimed = ((level + floor) & MASK)
        rest = ((u1000 - claimed) & MASK)
        return rest
      end
      is_focus = (category == focus)
      if is_focus
        return level
      end
      if point
        return u2
      end
      return u4
    end

    def float_swarm_total(entropy)
      u0 = 0
      u1 = 1
      u17 = 17
      total = u0
      category = u0
      loop do
        done = (category >= u17)
        if done
          break
        end
        weight = float_swarm_weight(entropy, category)
        total = ((total + weight) & MASK)
        category = ((category + u1) & MASK)
      end
      return total
    end

    def float_swarm_roll_span()
      span = 1000
      return span
    end

    def float_swarm_category(entropy, roll)
      u0 = 0
      u1 = 1
      u16 = 16
      reached = u0
      category = u0
      loop do
        done = (category >= u16)
        if done
          break
        end
        weight = float_swarm_weight(entropy, category)
        reached = ((reached + weight) & MASK)
        inside = (roll < reached)
        if inside
          return category
        end
        category = ((category + u1) & MASK)
      end
      return u16
    end

    def float_side_low(min_value, max_value, smallest_nonzero, negative)
      u1 = 1
      low = min_value
      if negative
        low = f64_neg(max_value)
      end
      under_smallest = (low < smallest_nonzero)
      if under_smallest
        low = smallest_nonzero
      end
      tiniest = bits2f(u1)
      under_tiniest = (low < tiniest)
      if under_tiniest
        low = tiniest
      end
      return low
    end

    def float_side_high(min_value, max_value, negative)
      high = max_value
      if negative
        high = f64_neg(min_value)
      end
      largest = f64_max()
      over_largest = (high > largest)
      if over_largest
        high = largest
      end
      return high
    end

    def float_magnitude_sample(category, low, high, coins, first, second)
      u0 = 0
      u1 = 1
      u2 = 2
      u3 = 3
      u4 = 4
      u5 = 5
      u6 = 6
      u7 = 7
      u8 = 8
      u14 = 14
      u16 = 16
      u52 = 52
      mantissa_mask = 4503599627370495
      none = nil
      band_low = low
      band_high = high
      banded = false
      near_zero = (category == u1)
      if near_zero
        bits_low = 4503599627370496
        bits_high = 4591870180066957721
        band_low = bits2f(bits_low)
        band_high = bits2f(bits_high)
        banded = true
      end
      subnormal = (category == u2)
      if subnormal
        band_low = bits2f(u1)
        band_high = bits2f(mantissa_mask)
        banded = true
      end
      near_max_for_add = (category == u6)
      if near_max_for_add
        bits_low = 9214364837600034816
        band_low = bits2f(bits_low)
        band_high = f64_max()
        banded = true
      end
      near_max_for_mul = (category == u7)
      if near_max_for_mul
        bits_low = 6908521828386340864
        bits_high = 6917529027641081855
        band_low = bits2f(bits_low)
        band_high = bits2f(bits_high)
        banded = true
      end
      near_sqrt_min_positive = (category == u8)
      if near_sqrt_min_positive
        bits_low = 2296835809958952960
        bits_high = 2310346608841064447
        band_low = bits2f(bits_low)
        band_high = bits2f(bits_high)
        banded = true
      end
      whole_side = (category == u16)
      if whole_side
        banded = true
      end
      if banded
        from_ = low
        band_above = (band_low > from_)
        if band_above
          from_ = band_low
        end
        to = high
        band_below = (band_high < to)
        if band_below
          to = band_high
        end
        empty = (from_ > to)
        if empty
          return none
        end
        magnitude = float_log_uniform_magnitude(from_, to, first, second)
        found = magnitude
        return found
      end
      low_bits = f2bits(low)
      high_bits = f2bits(high)
      near_one = (category == u3)
      if near_one
        one_bits = 4607182418800017408
        mantissa_bits = 52
        closeness = float_entropy_between(first, u1, mantissa_bits)
        span_shift = ((mantissa_bits - closeness) & MASK)
        span = ((u1 << span_shift) & MASK)
        above_from = one_bits
        low_over_one = (low_bits > above_from)
        if low_over_one
          above_from = low_bits
        end
        above_end = ((one_bits + span) & MASK)
        above_to = ((above_end - u1) & MASK)
        high_under_above = (high_bits < above_to)
        if high_under_above
          above_to = high_bits
        end
        double_span = ((span + span) & MASK)
        below_reach = ((double_span - u1) & MASK)
        below_from = ((one_bits - below_reach) & MASK)
        low_over_below = (low_bits > below_from)
        if low_over_below
          below_from = low_bits
        end
        below_to = ((one_bits - u1) & MASK)
        high_under_below = (high_bits < below_to)
        if high_under_below
          below_to = high_bits
        end
        above_open = (above_from <= above_to)
        below_open = (below_from <= below_to)
        below_first = float_entropy_coin(coins, u1)
        take_below = below_open
        above_first = (!below_first)
        prefer_above = (above_first && above_open)
        if prefer_above
          take_below = false
        end
        above_only = (!below_open)
        if above_only
          take_below = false
        end
        if take_below
          bits = float_entropy_between(second, below_from, below_to)
          value = bits2f(bits)
          found = value
          return found
        end
        if above_open
          bits = float_entropy_between(second, above_from, above_to)
          value = bits2f(bits)
          found = value
          return found
        end
        return none
      end
      integer = (category == u4)
      if integer
        one = 1.to_f
        limit_bits = 4845873199050653696
        limit = bits2f(limit_bits)
        from_ = low.ceil.to_f
        under_one = (from_ < one)
        if under_one
          from_ = one
        end
        to = f64_floor(high)
        over_limit = (to > limit)
        if over_limit
          to = limit
        end
        empty = (from_ > to)
        if empty
          return none
        end
        from_integer = f64_to_u64(from_)
        to_integer = f64_to_u64(to)
        picked = float_log_uniform_integer(from_integer, to_integer, first, second)
        value = picked.to_f
        found = value
        return found
      end
      half_integer = (category == u5)
      if half_integer
        zero = 0.to_f
        half = 0.5.to_f
        limit_bits = 4841369599423283198
        limit = bits2f(limit_bits)
        low_less_half = (low - half)
        from_ = low_less_half.ceil.to_f
        under_zero = (from_ < zero)
        if under_zero
          from_ = zero
        end
        high_less_half = (high - half)
        to = f64_floor(high_less_half)
        over_limit = (to > limit)
        if over_limit
          to = limit
        end
        empty = (from_ > to)
        if empty
          return none
        end
        from_integer = f64_to_u64(from_)
        to_integer = f64_to_u64(to)
        picked = float_log_uniform_integer(from_integer, to_integer, first, second)
        whole = picked.to_f
        value = (whole + half)
        found = value
        return found
      end
      binade_edge = (category == u14)
      if binade_edge
        low_exponent = (low_bits >> u52)
        low_mantissa = (low_bits & mantissa_mask)
        from_exponent = low_exponent
        subnormal_low = (low_exponent == u0)
        inside_binade = (low_mantissa != u0)
        past_power = (subnormal_low || inside_binade)
        if past_power
          from_exponent = ((low_exponent + u1) & MASK)
        end
        to_exponent = (high_bits >> u52)
        empty = (from_exponent > to_exponent)
        if empty
          return none
        end
        exponent = float_entropy_between(first, from_exponent, to_exponent)
        power = ((exponent << u52) & MASK)
        bits = power
        predecessor = ((power - u1) & MASK)
        want_predecessor = float_entropy_coin(coins, u1)
        predecessor_in_range = (predecessor >= low_bits)
        use_predecessor = (want_predecessor && predecessor_in_range)
        if use_predecessor
          bits = predecessor
        end
        value = bits2f(bits)
        found = value
        return found
      end
      return none
    end

    def float_signed_sample(category, min_value, max_value, smallest_nonzero, coins, first, second)
      u0 = 0
      u1 = 1
      u2 = 2
      negative = float_entropy_coin(coins, u0)
      tried = u0
      loop do
        done = (tried >= u2)
        if done
          break
        end
        low = float_side_low(min_value, max_value, smallest_nonzero, negative)
        high = float_side_high(min_value, max_value, negative)
        open = (low <= high)
        if open
          magnitude = float_magnitude_sample(category, low, high, coins, first, second)
          present = !magnitude.nil?
          if present
            value = magnitude
            if negative
              value = f64_neg(value)
            end
            found = value
            return found
          end
        end
        negative = (!negative)
        tried = ((tried + u1) & MASK)
      end
      none = nil
      return none
    end

    def float_point_option_count(category)
      u0 = 0
      u2 = 2
      u6 = 6
      u10 = 10
      u13 = 13
      endpoint = (category == u0)
      if endpoint
        return u6
      end
      from_infinity = (category >= u10)
      to_zero = (category <= u13)
      paired = (from_infinity && to_zero)
      if paired
        return u2
      end
      return u0
    end

    def float_point_option(category, min_value, max_value, index)
      u0 = 0
      u1 = 1
      u2 = 2
      u3 = 3
      u4 = 4
      u10 = 10
      u11 = 11
      u12 = 12
      one = 1.to_f
      endpoint = (category == u0)
      if endpoint
        want_min = (index == u0)
        if want_min
          return min_value
        end
        want_max = (index == u1)
        if want_max
          return max_value
        end
        want_above_min = (index == u2)
        if want_above_min
          above_min = f64_next_up(min_value)
          return above_min
        end
        want_min_plus_one = (index == u3)
        if want_min_plus_one
          min_plus_one = (min_value + one)
          return min_plus_one
        end
        want_max_less_one = (index == u4)
        if want_max_less_one
          max_less_one = (max_value - one)
          return max_less_one
        end
        below_max = f64_next_down(max_value)
        return below_max
      end
      magnitude = 0.to_f
      infinity = (category == u10)
      if infinity
        magnitude = f64_infinity()
      end
      max_magnitude = (category == u11)
      if max_magnitude
        magnitude = f64_max()
      end
      max_exact_integer = (category == u12)
      if max_exact_integer
        limit_bits = 4845873199050653696
        magnitude = bits2f(limit_bits)
      end
      negative = (index == u1)
      if negative
        negated = f64_neg(magnitude)
        return negated
      end
      return magnitude
    end

    def float_point_option_admitted(category, min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, index)
      u0 = 0
      u1 = 1
      false_ = false
      option = float_point_option(category, min_value, max_value, index)
      valid = float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, option)
      invalid = (!valid)
      if invalid
        return false_
      end
      option_bits = f2bits(option)
      earlier = u0
      loop do
        done = (earlier >= index)
        if done
          break
        end
        previous = float_point_option(category, min_value, max_value, earlier)
        previous_bits = f2bits(previous)
        repeat = (previous_bits == option_bits)
        if repeat
          return false_
        end
        earlier = ((earlier + u1) & MASK)
      end
      true_ = true
      return true_
    end

    def float_point_candidate(category, min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, word)
      u0 = 0
      u1 = 1
      count = float_point_option_count(category)
      admitted = u0
      index = u0
      loop do
        done = (index >= count)
        if done
          break
        end
        admit = float_point_option_admitted(category, min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, index)
        if admit
          admitted = ((admitted + u1) & MASK)
        end
        index = ((index + u1) & MASK)
      end
      none = nil
      nothing = (admitted == u0)
      if nothing
        return none
      end
      wanted = float_entropy_below(word, admitted)
      seen = u0
      index = u0
      loop do
        done = (index >= count)
        if done
          break
        end
        admit = float_point_option_admitted(category, min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, index)
        if admit
          hit = (seen == wanted)
          if hit
            option = float_point_option(category, min_value, max_value, index)
            found = option
            return found
          end
          seen = ((seen + u1) & MASK)
        end
        index = ((index + u1) & MASK)
      end
      return none
    end

    def float_nan_candidate(allow_nan, coins, first)
      u1 = 1
      u63 = 63
      exponent_field = 9218868437227405312
      quiet = 2251799813685248
      refused = (!allow_nan)
      if refused
        none = nil
        return none
      end
      sign_bit = (coins & u1)
      sign = ((sign_bit << u63) & MASK)
      payload = quiet
      canonical = float_entropy_coin(coins, u1)
      random = (!canonical)
      if random
        payload_top = ((quiet - u1) & MASK)
        low_payload = float_entropy_between(first, u1, payload_top)
        payload = (quiet | low_payload)
      end
      bits = (sign | exponent_field)
      bits = (bits | payload)
      value = bits2f(bits)
      found = value
      return found
    end

    def float_odd_denominator(word)
      u1 = 1
      u500 = 500
      half = float_entropy_between(word, u1, u500)
      double_ = ((half + half) & MASK)
      odd = ((double_ + u1) & MASK)
      return odd
    end

    def float_divides(numerator, denominator)
      quotient = (numerator / denominator)
      ceiling = quotient.ceil.to_f
      integral = (ceiling == quotient)
      return integral
    end

    def float_non_dyadic_candidate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, coins, first, second, third, fourth)
      u0 = 0
      u1 = 1
      u8 = 8
      u10 = 10
      u100 = 100
      u300 = 300
      five = 5.to_f
      one = 1.to_f
      magnitude = 0.to_f
      decimal = float_entropy_coin(coins, u1)
      if decimal
        digits = float_entropy_between(first, u1, u8)
        scale = u1
        raised = u0
        loop do
          done = (raised >= digits)
          if done
            break
          end
          scale = ((scale * u10) & MASK)
          raised = ((raised + u1) & MASK)
        end
        numerator_top = ((scale * u100) & MASK)
        numerator_integer = float_entropy_between(second, u1, numerator_top)
        numerator = numerator_integer.to_f
        five_divides = float_divides(numerator, five)
        if five_divides
          numerator = (numerator + one)
        end
        denominator = scale.to_f
        magnitude = (numerator / denominator)
      end
      fraction = (!decimal)
      if fraction
        denominator_integer = float_odd_denominator(first)
        numerator_integer = float_entropy_between(second, u1, u300)
        numerator = numerator_integer.to_f
        denominator = denominator_integer.to_f
        whole = float_divides(numerator, denominator)
        if whole
          numerator = (numerator + one)
        end
        magnitude = (numerator / denominator)
      end
      negated = f64_neg(magnitude)
      first_value = magnitude
      second_value = negated
      negative_first = float_entropy_coin(coins, u0)
      if negative_first
        first_value = negated
        second_value = magnitude
      end
      first_valid = float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, first_value)
      if first_valid
        found = first_value
        return found
      end
      second_valid = float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, second_value)
      if second_valid
        found = second_value
        return found
      end
      none = nil
      size = (max_value - min_value)
      size_nan = size.nan?
      if size_nan
        return none
      end
      size_infinite = !size.infinite?.nil?
      if size_infinite
        return none
      end
      denominator_integer = float_odd_denominator(third)
      numerator_top = ((denominator_integer - u1) & MASK)
      numerator_integer = float_entropy_between(fourth, u1, numerator_top)
      numerator = numerator_integer.to_f
      denominator = denominator_integer.to_f
      ratio = (numerator / denominator)
      offset = (size * ratio)
      value = (min_value + offset)
      found = value
      return found
    end

    def float_category_candidate(category, min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, coins, first, second, third, fourth)
      u0 = 0
      u8 = 8
      u9 = 9
      u14 = 14
      u15 = 15
      candidate = nil
      options = float_point_option_count(category)
      pointed = (options > u0)
      if pointed
        candidate = float_point_candidate(category, min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, first)
      end
      not_endpoint = (category > u0)
      through_bands = (category <= u8)
      band = (not_endpoint && through_bands)
      binade_edge = (category == u14)
      signed_ = (band || binade_edge)
      if signed_
        candidate = float_signed_sample(category, min_value, max_value, smallest_nonzero, coins, first, second)
      end
      nan = (category == u9)
      if nan
        candidate = float_nan_candidate(allow_nan, coins, first)
      end
      non_dyadic = (category == u15)
      if non_dyadic
        candidate = float_non_dyadic_candidate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, coins, first, second, third, fourth)
      end
      present = !candidate.nil?
      if present
        value = candidate
        valid = float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, value)
        if valid
          return candidate
        end
      end
      none = nil
      return none
    end

    def float_default_candidate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, coins, first, second, third)
      u0 = 0
      u1 = 1
      u16 = 16
      one = 1.to_f
      log_uniform = float_entropy_coin(coins, u0)
      if log_uniform
        sign_coins = (coins >> u1)
        sampled = float_signed_sample(u16, min_value, max_value, smallest_nonzero, sign_coins, first, second)
        present = !sampled.nil?
        if present
          value = sampled
          valid = float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, value)
          if valid
            return value
          end
        end
      end
      largest = f64_max()
      lowest = f64_neg(largest)
      low = min_value
      under = (low < lowest)
      if under
        low = lowest
      end
      high = max_value
      over = (high > largest)
      if over
        high = largest
      end
      unit = float_entropy_unit(third)
      rest = (one - unit)
      low_share = (low * rest)
      high_share = (high * unit)
      value = (low_share + high_share)
      valid = float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, value)
      if valid
        return value
      end
      simplest = float_simplest(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero)
      has_simplest = !simplest.nil?
      if has_simplest
        fallback = simplest
        return fallback
      end
      return value
    end

    def text_biased_rank_span()
      span = 128
      return span
    end

    def text_bias_threshold()
      threshold = 900
      return threshold
    end

    def text_rank_span(alphabet, biased)
      size = alphabet_size(alphabet)
      span = size
      if biased
        biased_span = text_biased_rank_span()
        narrower = (biased_span < size)
        if narrower
          span = biased_span
        end
      end
      return span
    end

    def generation_request_kind(attempts, pending_mutations, mutation_streak)
      u0 = 0
      simplest = 1
      mutation = 2
      random = 3
      first = (attempts == u0)
      if first
        return simplest
      end
      has_mutation = (pending_mutations > u0)
      if has_mutation
        brood = mutation_attempt_count()
        fresh_due = (mutation_streak >= brood)
        if fresh_due
          return random
        end
        return mutation
      end
      return random
    end

    def generation_enqueue_mutations(request_kind, valid)
      random = 3
      u10 = 10
      is_random = (request_kind == random)
      corpus_ready = (valid >= u10)
      enqueue = (is_random && corpus_ready)
      return enqueue
    end

    def generation_should_continue(valid, examples)
      continue_ = (valid < examples)
      return continue_
    end

    def generation_novelty_action(request_kind, exact_seen)
      skip = 0
      execute = 1
      execute_and_record = 2
      mutation = 2
      is_mutation = (request_kind == mutation)
      if is_mutation
        if exact_seen
          return skip
        end
        return execute_and_record
      end
      return execute
    end

    def generation_rare_label_permille()
      permille = 250
      return permille
    end

    def generation_label_rare(observed, valid, min_permille)
      true_ = true
      false_ = false
      thousand = 1000
      max_scaled = 18446744073709551
      floor = generation_rare_label_permille()
      threshold = min_permille
      below_floor = (threshold < floor)
      if below_floor
        threshold = floor
      end
      over_rate = (threshold > thousand)
      if over_rate
        short_ = (observed < valid)
        return short_
      end
      lhs_overflows = (observed > max_scaled)
      if lhs_overflows
        return false_
      end
      rhs_overflows = (valid > max_scaled)
      if rhs_overflows
        return true_
      end
      lhs = ((observed * thousand) & MASK)
      rhs = ((valid * threshold) & MASK)
      rare = (lhs < rhs)
      return rare
    end

    def generation_mutation_admission(request_kind, valid, pending, held_rare_label)
      none = 0
      back = 1
      front = 2
      brood = mutation_attempt_count()
      full = (pending >= brood)
      if full
        return none
      end
      base = generation_enqueue_mutations(request_kind, valid)
      if base
        if held_rare_label
          return front
        end
        return back
      end
      if held_rare_label
        return front
      end
      return none
    end

    def mutation_index(count, entropy)
      u0 = 0
      u32 = 32
      u4294967296 = 4294967296
      empty = (count == u0)
      too_large = (count > u4294967296)
      invalid = (empty || too_large)
      if invalid
        none = nil
        return none
      end
      slot = (entropy >> u32)
      scaled = ((slot * count) & MASK)
      index = (scaled >> u32)
      some = index
      return some
    end

    def mutation_distinct_index(count, first, entropy)
      u1 = 1
      too_small = (count <= u1)
      first_invalid = (first >= count)
      invalid = (too_small || first_invalid)
      if invalid
        none = nil
        return none
      end
      remaining = ((count - u1) & MASK)
      raw_opt = mutation_index(remaining, entropy)
      raw = raw_opt
      past_hole = (raw >= first)
      index = raw
      if past_hole
        index = ((raw + u1) & MASK)
      end
      some = index
      return some
    end

    def mutation_use_first(entropy)
      u0 = 0
      u1 = 1
      low = (entropy & u1)
      first = (low == u0)
      return first
    end

    def mutation_attempt_count()
      u6 = 6
      return u6
    end

    def mutation_attempt_randomized(attempt)
      u2 = 2
      randomized = (attempt >= u2)
      return randomized
    end

    def stateful_feature_generation_raw()
      u0 = 0
      return u0
    end

    def stateful_feature_probability(raw)
      u254 = 254
      f255 = 255.to_f
      bounded = raw
      too_large = (bounded > u254)
      if too_large
        bounded = u254
      end
      value = bounded.to_f
      probability = (value / f255)
      return probability
    end

    def stateful_feature_forced(candidate_count, is_candidate, decided, disabled)
      u1 = 1
      false_ = false
      last = (candidate_count == u1)
      must_enable = (last && is_candidate)
      if must_enable
        forced = false_
        return forced
      end
      if decided
        forced = disabled
        return forced
      end
      free = nil
      return free
    end

    def stateful_rule_probe_count()
      u3 = 3
      return u3
    end

    def stateful_fallback_max_good(rule_count, known_bad_count)
      u0 = 0
      valid = (known_bad_count < rule_count)
      if valid
        remaining = ((rule_count - known_bad_count) & MASK)
        return remaining
      end
      return u0
    end

    def stateful_fallback_accept(allowed_count, speculative)
      accept = (allowed_count > speculative)
      return accept
    end

    def stateful_choice_protocol(data, start, remaining)
      i0 = 0
      u0 = 0
      u1 = 1
      u2 = 2
      u3 = 3
      first = i0
      third = i0
      seen = u0
      pos = start
      left = remaining
      loop do
        enough = (seen >= u3)
        if enough
          break
        end
        exhausted = (left == u0)
        if exhausted
          return u1
        end
        end_ = choice_entry_end(data, pos, u0)
        bad_entry = (end_ == i0)
        if bad_entry
          return u1
        end
        key = keyed_entry_key(data, pos)
        named = !key.nil?
        positional = (!named)
        if positional
          is_first = (seen == u0)
          if is_first
            first = pos
          end
          is_third = (seen == u2)
          if is_third
            third = pos
          end
          seen = ((seen + u1) & MASK)
        end
        pos = end_
        left = ((left - u1) & MASK)
      end
      first_choice = deserialize_boolean_choice(data, first)
      first_boolean = !first_choice.nil?
      if first_boolean
        first_value = first_choice
        if first_value
          return u3
        end
      end
      tag = data.getbyte(third)
      integer = (tag == u0)
      if integer
        return u2
      end
      return u1
    end

    def stateful_stop_forced(steps_drawn, steps_rejected, step_count)
      u0 = 0
      u10 = 10
      u1000 = 1000
      u_max = 18446744073709551615
      mul_ceiling = 1844674407370955161
      true_ = true
      false_ = false
      successful = u0
      progressed = (steps_drawn > steps_rejected)
      if progressed
        successful = ((steps_drawn - steps_rejected) & MASK)
      end
      done = (successful >= step_count)
      if done
        halt = true_
        return halt
      end
      attempts = u_max
      fits = (step_count <= mul_ceiling)
      if fits
        attempts = ((step_count * u10) & MASK)
      end
      stalled = (successful == u0)
      if stalled
        below_floor = (attempts < u1000)
        if below_floor
          attempts = u1000
        end
      end
      spent = (steps_drawn >= attempts)
      if spent
        halt = true_
        return halt
      end
      first = (steps_drawn == u0)
      if first
        go_ = false_
        return go_
      end
      free = nil
      return free
    end

    def stateful_continue_forced(steps_drawn, steps_rejected, step_count)
      stop = stateful_stop_forced(steps_drawn, steps_rejected, step_count)
      decided = !stop.nil?
      if decided
        halt = stop
        go_ = (!halt)
        forced = go_
        return forced
      end
      free = nil
      return free
    end

    def stateful_continue_probability()
      f1 = 1.to_f
      f2_32 = 4294967296.to_f
      stop = (f1 / f2_32)
      probability = (f1 - stop)
      return probability
    end

    def stateful_pool_position(active_count, newest_offset)
      u1 = 1
      valid = (newest_offset < active_count)
      invalid = (!valid)
      if invalid
        none = nil
        return none
      end
      last = ((active_count - u1) & MASK)
      position = ((last - newest_offset) & MASK)
      some = position
      return some
    end

    def stateful_fresh_id_window(max_plus_one)
      u1 = 1
      window = ((max_plus_one + u1) & MASK)
      return window
    end

    def stateful_set_choice_window(max_plus_one)
      window = max_plus_one
      return window
    end

    def stateful_fresh_id_fallback_step(candidate, used_id)
      u1 = 1
      next_ = candidate
      taken = (used_id == candidate)
      if taken
        next_ = ((candidate + u1) & MASK)
      end
      return next_
    end

    def stateful_fresh_id_accepts(value, window_hi, in_use)
      in_window = (value <= window_hi)
      unused = (!in_use)
      accepts = (in_window && unused)
      return accepts
    end

    def stateful_set_choice_accepts(value, window_hi)
      accepts = (value <= window_hi)
      return accepts
    end

    def stateful_set_choice_better(candidate, raw, best)
      at_or_below = (candidate <= raw)
      above_best = (candidate > best)
      better = (at_or_below && above_best)
      return better
    end

    def outcome_is_failure(outcome)
      interesting = 4
      is_failure = (outcome == interesting)
      return is_failure
    end

    def shrink_accept(outcome, origin_matches)
      is_failure = outcome_is_failure(outcome)
      accept = (is_failure && origin_matches)
      return accept
    end

    def shrink_cost_progress(candidate_cost, current_cost, stream_simpler)
      false_ = false
      true_ = true
      cheaper = (candidate_cost < current_cost)
      if cheaper
        return true_
      end
      dearer = (candidate_cost > current_cost)
      if dearer
        return false_
      end
      return stream_simpler
    end

    def generation_rejection_limit(base, valid)
      u100 = 100
      max = 18446744073709551615
      max_valid = 184467440737095516
      scale_overflows = (valid > max_valid)
      if scale_overflows
        return max
      end
      earned = ((valid * u100) & MASK)
      remaining = ((max - earned) & MASK)
      add_overflows = (base > remaining)
      if add_overflows
        return max
      end
      limit = ((base + earned) & MASK)
      return limit
    end

    def health_filter_too_much(rejections, valid, suppressed)
      u10 = 10
      u50 = 50
      many_rejections = (rejections >= u50)
      few_valid = (valid < u10)
      active = (!suppressed)
      unhealthy = (many_rejections && few_valid)
      report = (unhealthy && active)
      return report
    end

    def choice_budget_exhausted(draw_count)
      buffer_size = 8192
      exhausted = (draw_count >= buffer_size)
      return exhausted
    end

    def health_data_too_large(overruns, valid, suppressed)
      u10 = 10
      u20 = 20
      many_overruns = (overruns >= u20)
      few_valid = (valid < u10)
      active = (!suppressed)
      unhealthy = (many_overruns && few_valid)
      report = (unhealthy && active)
      return report
    end

    def health_large_base_example(overran, outcome, draw_count, suppressed)
      u0 = 0
      half_buffer = 4096
      valid = (outcome == u0)
      large = (draw_count > half_buffer)
      large_valid = (valid && large)
      unhealthy = (overran || large_valid)
      active = (!suppressed)
      report = (unhealthy && active)
      return report
    end

    def health_too_slow(generation_us, valid, suppressed)
      u10 = 10
      one_second_us = 1000000
      slow = (generation_us > one_second_us)
      few_valid = (valid < u10)
      active = (!suppressed)
      unhealthy = (slow && few_valid)
      report = (unhealthy && active)
      return report
    end

    def coverage_failed(observed, valid, min_permille)
      true_ = true
      false_ = false
      zero = 0
      thousand = 1000
      max_scaled = 18446744073709551
      never = (observed == zero)
      if never
        return true_
      end
      no_rate = (min_permille == zero)
      if no_rate
        return false_
      end
      lhs_overflows = (observed > max_scaled)
      if lhs_overflows
        return false_
      end
      over_rate = (min_permille > thousand)
      if over_rate
        failed_clamped = (observed < valid)
        return failed_clamped
      end
      rhs_overflows = (valid > max_scaled)
      if rhs_overflows
        return true_
      end
      lhs = ((observed * thousand) & MASK)
      rhs = ((min_permille * valid) & MASK)
      failed = (lhs < rhs)
      return failed
    end

    def shrink_candidate_at(current, ordinal)
      u0 = 0
      u1 = 1
      u4 = 4
      u5 = 5
      empty = (current == u0)
      if empty
        none_empty = nil
        return none_empty
      end
      within_current = (ordinal < current)
      within_prefix = (ordinal < u5)
      linear = (within_current && within_prefix)
      if linear
        some_linear = ordinal
        return some_linear
      end
      prefix_exhausts = (current <= u5)
      if prefix_exhausts
        none_prefix = nil
        return none_prefix
      end
      seen = u5
      lower = u4
      loop do
        gap = ((current - lower) & MASK)
        exhausted = (gap <= u1)
        if exhausted
          break
        end
        half = (gap >> u1)
        probe = ((lower + half) & MASK)
        want_probe = (ordinal == seen)
        if want_probe
          some_probe = probe
          return some_probe
        end
        seen = ((seen + u1) & MASK)
        lower = probe
      end
      none = nil
      return none
    end

    def shrink_next_shrinks(phase, feedback, shrinks)
      u1 = 1
      phase_baseline = 0
      phase_verify = 3
      feedback_accepted = 2
      in_baseline = (phase == phase_baseline)
      if in_baseline
        return shrinks
      end
      in_verify = (phase == phase_verify)
      if in_verify
        return shrinks
      end
      accepted = (feedback == feedback_accepted)
      if accepted
        bumped = ((shrinks + u1) & MASK)
        return bumped
      end
      return shrinks
    end

    def shrink_sweep_again(improved, shrinks, max_shrinks)
      u0 = 0
      false_ = false
      true_ = true
      idle = (!improved)
      if idle
        return false_
      end
      uncapped = (max_shrinks == u0)
      if uncapped
        return true_
      end
      under = (shrinks < max_shrinks)
      return under
    end

    def shrink_next_stall(stall, feedback)
      u0 = 0
      u1 = 1
      feedback_skip = 0
      feedback_accepted = 2
      accepted = (feedback == feedback_accepted)
      if accepted
        return u0
      end
      skipped = (feedback == feedback_skip)
      if skipped
        return stall
      end
      bumped = ((stall + u1) & MASK)
      return bumped
    end

    def shrink_next_span_cursor(phase, feedback, span_cursor)
      u0 = 0
      u1 = 1
      phase_delete = 1
      feedback_accepted = 2
      in_delete = (phase == phase_delete)
      if in_delete
        accepted = (feedback == feedback_accepted)
        if accepted
          return u0
        end
        advanced = ((span_cursor + u1) & MASK)
        return advanced
      end
      return u0
    end

    def shrink_next_paid_cursor(phase, feedback, paid_cursor)
      u0 = 0
      u1 = 1
      phase_paid = 12
      feedback_skip = 0
      feedback_accepted = 2
      in_paid = (phase == phase_paid)
      if in_paid
        accepted = (feedback == feedback_accepted)
        if accepted
          return u0
        end
        skipped = (feedback == feedback_skip)
        if skipped
          advanced = ((paid_cursor + u1) & MASK)
          return advanced
        end
        return paid_cursor
      end
      return u0
    end

    def shrink_delete_paid_variant(ordinal, widened)
      u0 = 0
      u1 = 1
      i0 = 0
      i1 = 1
      step = ordinal
      if widened
        plain = (ordinal == u0)
        if plain
          some_plain = i0
          return some_plain
        end
        step = ((ordinal - u1) & MASK)
      end
      down = (step == u0)
      if down
        minus_one = (i0 - i1)
        some_down = minus_one
        return some_down
      end
      up = (step == u1)
      if up
        some_up = i1
        return some_up
      end
      none = nil
      return none
    end

    def shrink_next_raise_cursor(phase, feedback, raise_cursor)
      u0 = 0
      u1 = 1
      phase_raise = 13
      feedback_skip = 0
      feedback_accepted = 2
      in_raise = (phase == phase_raise)
      if in_raise
        accepted = (feedback == feedback_accepted)
        if accepted
          return u0
        end
        skipped = (feedback == feedback_skip)
        if skipped
          advanced = ((raise_cursor + u1) & MASK)
          return advanced
        end
        return raise_cursor
      end
      return u0
    end

    def shrink_raise_candidate(current_index, max_index, ordinal)
      u0 = 0
      u1 = 1
      below_max = (current_index < max_index)
      at_max = (!below_max)
      if at_max
        none_max = nil
        return none_max
      end
      next_ = ((current_index + u1) & MASK)
      first = (ordinal == u0)
      if first
        some_next = next_
        return some_next
      end
      second = (ordinal == u1)
      beyond_next = (next_ < max_index)
      jumps = (second && beyond_next)
      if jumps
        some_max = max_index
        return some_max
      end
      none = nil
      return none
    end

    def shrink_next_position(phase, feedback, position)
      u0 = 0
      u1 = 1
      phase_lower = 2
      feedback_skip = 0
      feedback_accepted = 2
      in_lower = (phase == phase_lower)
      if in_lower
        accepted = (feedback == feedback_accepted)
        if accepted
          return u0
        end
        skipped = (feedback == feedback_skip)
        if skipped
          advanced = ((position + u1) & MASK)
          return advanced
        end
        return position
      end
      return u0
    end

    def shrink_next_shorten_cursor(phase, feedback, shorten_cursor)
      u0 = 0
      u1 = 1
      phase_shorten = 11
      feedback_skip = 0
      feedback_accepted = 2
      in_shorten = (phase == phase_shorten)
      if in_shorten
        accepted = (feedback == feedback_accepted)
        if accepted
          return u0
        end
        skipped = (feedback == feedback_skip)
        if skipped
          advanced = ((shorten_cursor + u1) & MASK)
          return advanced
        end
        return shorten_cursor
      end
      return u0
    end

    def shrink_next_character_cursor(phase, feedback, character_cursor)
      u0 = 0
      u1 = 1
      phase_character = 10
      feedback_skip = 0
      feedback_accepted = 2
      in_character = (phase == phase_character)
      if in_character
        accepted = (feedback == feedback_accepted)
        if accepted
          return u0
        end
        skipped = (feedback == feedback_skip)
        if skipped
          advanced = ((character_cursor + u1) & MASK)
          return advanced
        end
        return character_cursor
      end
      return u0
    end

    def shrink_next_descendant_cursor(phase, feedback, descendant_cursor)
      u0 = 0
      u1 = 1
      phase_descendant = 9
      feedback_skip = 0
      feedback_accepted = 2
      in_descendant = (phase == phase_descendant)
      if in_descendant
        accepted = (feedback == feedback_accepted)
        if accepted
          return u0
        end
        skipped = (feedback == feedback_skip)
        if skipped
          advanced = ((descendant_cursor + u1) & MASK)
          return advanced
        end
        return descendant_cursor
      end
      return u0
    end

    def shrink_descendant_worthwhile(ancestor_choices, descendant_choices)
      u0 = 0
      nonempty = (descendant_choices > u0)
      shorter = (descendant_choices < ancestor_choices)
      worthwhile = (nonempty && shorter)
      return worthwhile
    end

    def shrink_next_trivial_cursor(phase, feedback, trivial_cursor)
      u0 = 0
      u1 = 1
      phase_trivial = 8
      feedback_accepted = 2
      in_trivial = (phase == phase_trivial)
      if in_trivial
        accepted = (feedback == feedback_accepted)
        if accepted
          return u0
        end
        advanced = ((trivial_cursor + u1) & MASK)
        return advanced
      end
      return u0
    end

    def shrink_trivial_worthwhile(rewritable)
      u0 = 0
      worthwhile = (rewritable > u0)
      return worthwhile
    end

    def shrink_next_reorder_cursor(phase, feedback, reorder_cursor)
      u0 = 0
      u1 = 1
      phase_reorder = 7
      feedback_accepted = 2
      in_reorder = (phase == phase_reorder)
      if in_reorder
        accepted = (feedback == feedback_accepted)
        if accepted
          return u0
        end
        advanced = ((reorder_cursor + u1) & MASK)
        return advanced
      end
      return u0
    end

    def shrink_next_pair_cursor(phase, feedback, pair_cursor)
      u0 = 0
      u1 = 1
      phase_pair = 6
      feedback_skip = 0
      feedback_accepted = 2
      in_pair = (phase == phase_pair)
      if in_pair
        accepted = (feedback == feedback_accepted)
        if accepted
          return u0
        end
        skipped = (feedback == feedback_skip)
        if skipped
          advanced = ((pair_cursor + u1) & MASK)
          return advanced
        end
        return pair_cursor
      end
      return u0
    end

    def shrink_pair_count(draw_count)
      u0 = 0
      u1 = 1
      empty = (draw_count < u1)
      if empty
        return u0
      end
      pairs = ((draw_count - u1) & MASK)
      return pairs
    end

    def shrink_next_duplicate_cursor(phase, feedback, duplicate_cursor)
      u0 = 0
      u1 = 1
      phase_duplicate = 5
      feedback_skip = 0
      feedback_accepted = 2
      in_duplicate = (phase == phase_duplicate)
      if in_duplicate
        accepted = (feedback == feedback_accepted)
        if accepted
          return u0
        end
        skipped = (feedback == feedback_skip)
        if skipped
          advanced = ((duplicate_cursor + u1) & MASK)
          return advanced
        end
        return duplicate_cursor
      end
      return u0
    end

    def shrink_next_ordinal(phase, feedback, ordinal)
      u0 = 0
      u1 = 1
      phase_lower = 2
      phase_duplicate = 5
      phase_pair = 6
      phase_descendant = 9
      phase_character = 10
      phase_shorten = 11
      phase_paid = 12
      phase_raise = 13
      feedback_rejected = 1
      is_lower = (phase == phase_lower)
      is_duplicate = (phase == phase_duplicate)
      is_pair = (phase == phase_pair)
      is_descendant = (phase == phase_descendant)
      is_character = (phase == phase_character)
      is_shorten = (phase == phase_shorten)
      is_paid = (phase == phase_paid)
      is_raise = (phase == phase_raise)
      walks_schedule = (is_lower || is_duplicate)
      walks_ordinal = (walks_schedule || is_pair)
      walks_span = (walks_ordinal || is_descendant)
      walks_string = (walks_span || is_character)
      walks_shorten = (walks_string || is_shorten)
      walks_paid = (walks_shorten || is_paid)
      in_lower = (walks_paid || is_raise)
      if in_lower
        rejected = (feedback == feedback_rejected)
        if rejected
          advanced = ((ordinal + u1) & MASK)
          return advanced
        end
        return u0
      end
      return u0
    end

    def shrink_next_phase(phase, feedback, span_cursor, duplicate_cursor, position, pair_cursor, reorder_cursor, trivial_cursor, descendant_cursor, character_cursor, shorten_cursor, paid_cursor, raise_cursor, shrinks, stall, max_shrinks, max_stall, draw_count, span_count)
      u0 = 0
      phase_baseline = 0
      phase_delete = 1
      phase_lower = 2
      phase_verify = 3
      phase_done = 4
      phase_duplicate = 5
      phase_pair = 6
      phase_reorder = 7
      phase_trivial = 8
      phase_descendant = 9
      phase_character = 10
      phase_shorten = 11
      phase_paid = 12
      phase_raise = 13
      feedback_accepted = 2
      accepted = (feedback == feedback_accepted)
      next_ = phase
      in_baseline = (phase == phase_baseline)
      if in_baseline
        next_ = phase_lower
        if accepted
          next_ = phase_delete
        end
      end
      in_delete = (phase == phase_delete)
      if in_delete
        if accepted
          next_ = phase_baseline
        end
      end
      in_paid = (phase == phase_paid)
      if in_paid
        if accepted
          next_ = phase_baseline
        end
      end
      in_raise = (phase == phase_raise)
      if in_raise
        if accepted
          next_ = phase_baseline
        end
      end
      in_descendant = (phase == phase_descendant)
      if in_descendant
        if accepted
          next_ = phase_baseline
        end
      end
      in_verify = (phase == phase_verify)
      if in_verify
        next_ = phase_done
      end
      settled = (next_ != phase_done)
      if settled
        shrinks_next = shrink_next_shrinks(phase, feedback, shrinks)
        stall_next = shrink_next_stall(stall, feedback)
        shrinks_capped = (max_shrinks != u0)
        over_shrinks = (shrinks_next >= max_shrinks)
        stop_shrinks = (shrinks_capped && over_shrinks)
        if stop_shrinks
          next_ = phase_verify
        end
        stall_capped = (max_stall != u0)
        over_stall = (stall_next >= max_stall)
        stop_stall = (stall_capped && over_stall)
        if stop_stall
          next_ = phase_verify
        end
      end
      lands_delete = (next_ == phase_delete)
      if lands_delete
        span_next = shrink_next_span_cursor(phase, feedback, span_cursor)
        spans_left = (span_next < span_count)
        spans_done = (!spans_left)
        if spans_done
          next_ = phase_paid
        end
      end
      lands_paid = (next_ == phase_paid)
      if lands_paid
        paid_next = shrink_next_paid_cursor(phase, feedback, paid_cursor)
        paid_left = (paid_next < span_count)
        paid_done = (!paid_left)
        if paid_done
          next_ = phase_trivial
        end
      end
      lands_trivial = (next_ == phase_trivial)
      if lands_trivial
        trivial_next = shrink_next_trivial_cursor(phase, feedback, trivial_cursor)
        trivial_left = (trivial_next < span_count)
        trivial_done = (!trivial_left)
        if trivial_done
          next_ = phase_descendant
        end
      end
      lands_descendant = (next_ == phase_descendant)
      if lands_descendant
        descendant_next = shrink_next_descendant_cursor(phase, feedback, descendant_cursor)
        descendants_left = (descendant_next < span_count)
        descendants_done = (!descendants_left)
        if descendants_done
          next_ = phase_reorder
        end
      end
      lands_reorder = (next_ == phase_reorder)
      if lands_reorder
        reorder_next = shrink_next_reorder_cursor(phase, feedback, reorder_cursor)
        siblings_left = (reorder_next < span_count)
        siblings_done = (!siblings_left)
        if siblings_done
          next_ = phase_duplicate
        end
      end
      lands_duplicate = (next_ == phase_duplicate)
      if lands_duplicate
        duplicate_next = shrink_next_duplicate_cursor(phase, feedback, duplicate_cursor)
        duplicate_left = (duplicate_next < draw_count)
        duplicate_done = (!duplicate_left)
        if duplicate_done
          next_ = phase_lower
        end
      end
      lands_lower = (next_ == phase_lower)
      if lands_lower
        position_next = shrink_next_position(phase, feedback, position)
        draws_left = (position_next < draw_count)
        draws_done = (!draws_left)
        if draws_done
          next_ = phase_pair
        end
      end
      lands_pair = (next_ == phase_pair)
      if lands_pair
        pair_next = shrink_next_pair_cursor(phase, feedback, pair_cursor)
        pair_count = shrink_pair_count(draw_count)
        pairs_left = (pair_next < pair_count)
        pairs_done = (!pairs_left)
        if pairs_done
          next_ = phase_shorten
        end
      end
      lands_shorten = (next_ == phase_shorten)
      if lands_shorten
        shorten_next = shrink_next_shorten_cursor(phase, feedback, shorten_cursor)
        shorten_left = (shorten_next < draw_count)
        shorten_done = (!shorten_left)
        if shorten_done
          next_ = phase_character
        end
      end
      lands_character = (next_ == phase_character)
      if lands_character
        character_next = shrink_next_character_cursor(phase, feedback, character_cursor)
        characters_left = (character_next < draw_count)
        characters_done = (!characters_left)
        if characters_done
          next_ = phase_raise
        end
      end
      lands_raise = (next_ == phase_raise)
      if lands_raise
        raise_next = shrink_next_raise_cursor(phase, feedback, raise_cursor)
        raisable = shrink_pair_count(draw_count)
        raises_left = (raise_next < raisable)
        raises_done = (!raises_left)
        if raises_done
          next_ = phase_verify
        end
      end
      return next_
    end

    def shrink_request_kind(phase, span_cursor, duplicate_cursor, position, pair_cursor, reorder_cursor, trivial_cursor, descendant_cursor, character_cursor, shorten_cursor, paid_cursor, raise_cursor, draw_count, span_count)
      phase_baseline = 0
      phase_delete = 1
      phase_lower = 2
      phase_verify = 3
      phase_duplicate = 5
      phase_pair = 6
      phase_reorder = 7
      phase_trivial = 8
      phase_descendant = 9
      phase_character = 10
      phase_shorten = 11
      phase_paid = 12
      phase_raise = 13
      request_done = 0
      request_baseline = 1
      request_delete = 2
      request_lower = 3
      request_verify = 4
      request_duplicates = 5
      request_pair = 6
      request_reorder = 7
      request_trivial = 8
      request_descendant = 9
      request_character = 10
      request_shorten = 11
      request_paid = 12
      request_raise = 13
      is_baseline = (phase == phase_baseline)
      if is_baseline
        return request_baseline
      end
      is_delete = (phase == phase_delete)
      if is_delete
        spans_left = (span_cursor < span_count)
        if spans_left
          return request_delete
        end
        return request_done
      end
      is_paid = (phase == phase_paid)
      if is_paid
        paid_left = (paid_cursor < span_count)
        if paid_left
          return request_paid
        end
        return request_done
      end
      is_trivial = (phase == phase_trivial)
      if is_trivial
        trivial_left = (trivial_cursor < span_count)
        if trivial_left
          return request_trivial
        end
        return request_done
      end
      is_descendant = (phase == phase_descendant)
      if is_descendant
        descendants_left = (descendant_cursor < span_count)
        if descendants_left
          return request_descendant
        end
        return request_done
      end
      is_reorder = (phase == phase_reorder)
      if is_reorder
        siblings_left = (reorder_cursor < span_count)
        if siblings_left
          return request_reorder
        end
        return request_done
      end
      is_duplicate = (phase == phase_duplicate)
      if is_duplicate
        groups_left = (duplicate_cursor < draw_count)
        if groups_left
          return request_duplicates
        end
        return request_done
      end
      is_lower = (phase == phase_lower)
      if is_lower
        draws_left = (position < draw_count)
        if draws_left
          return request_lower
        end
        return request_done
      end
      is_pair = (phase == phase_pair)
      if is_pair
        pair_count = shrink_pair_count(draw_count)
        pairs_left = (pair_cursor < pair_count)
        if pairs_left
          return request_pair
        end
        return request_done
      end
      is_shorten = (phase == phase_shorten)
      if is_shorten
        shorten_left = (shorten_cursor < draw_count)
        if shorten_left
          return request_shorten
        end
        return request_done
      end
      is_character = (phase == phase_character)
      if is_character
        characters_left = (character_cursor < draw_count)
        if characters_left
          return request_character
        end
        return request_done
      end
      is_raise = (phase == phase_raise)
      if is_raise
        raisable = shrink_pair_count(draw_count)
        raises_left = (raise_cursor < raisable)
        if raises_left
          return request_raise
        end
        return request_done
      end
      is_verify = (phase == phase_verify)
      if is_verify
        return request_verify
      end
      return request_done
    end

    def shrink_request_span(span_cursor, span_count)
      u0 = 0
      u1 = 1
      spans_left = (span_cursor < span_count)
      exhausted = (!spans_left)
      if exhausted
        return u0
      end
      last = ((span_count - u1) & MASK)
      index = ((last - span_cursor) & MASK)
      return index
    end

    def shrink_duplicate_worthwhile(members, current_index)
      u0 = 0
      u2 = 2
      shared = (members >= u2)
      lowerable = (current_index != u0)
      worthwhile = (shared && lowerable)
      return worthwhile
    end

    def shrink_pair_base(left_index, right_index)
      right_smaller = (right_index < left_index)
      if right_smaller
        return right_index
      end
      return left_index
    end

    def shrink_pair_worthwhile(left_index, right_index)
      u0 = 0
      base = shrink_pair_base(left_index, right_index)
      worthwhile = (base != u0)
      return worthwhile
    end

    def shrink_pair_candidate(index, base, candidate)
      rising = (candidate > base)
      if rising
        none_rising = nil
        return none_rising
      end
      shift = ((base - candidate) & MASK)
      too_small = (index < shift)
      if too_small
        none_small = nil
        return none_small
      end
      shifted = ((index - shift) & MASK)
      some_shifted = shifted
      return some_shifted
    end

    def shrink_candidate_count(current)
      u0 = 0
      u1 = 1
      ordinal = u0
      loop do
        candidate = shrink_candidate_at(current, ordinal)
        present = !candidate.nil?
        done = (!present)
        if done
          break
        end
        ordinal = ((ordinal + u1) & MASK)
      end
      return ordinal
    end

    def length_p_continue(min_size, max_size, has_max)
      f0_5 = 0.5.to_f
      f1 = 1.to_f
      f2 = 2.to_f
      f5 = 5.to_f
      f0_99 = 0.99.to_f
      minimum = (min_size & MASK)
      min_f = minimum.to_f
      infinity = f64_infinity()
      max_f = infinity
      if has_max
        bounded = (max_size & MASK)
        max_f = bounded.to_f
      end
      doubled = (min_f * f2)
      plus_five = (min_f + f5)
      floor = doubled
      five_larger = (plus_five > doubled)
      if five_larger
        floor = plus_five
      end
      span = (min_f + max_f)
      midpoint = (span * f0_5)
      average = floor
      midpoint_smaller = (midpoint < floor)
      if midpoint_smaller
        average = midpoint
      end
      desired_extra = (average - min_f)
      max_extra = (max_f - min_f)
      saturated = (desired_extra >= max_extra)
      if saturated
        return f0_99
      end
      unbounded = !max_f.infinite?.nil?
      if unbounded
        denominator = (f1 + desired_extra)
        ratio = (f1 / denominator)
        p = (f1 - ratio)
        return p
      end
      denominator = (f2 + desired_extra)
      ratio = (f1 / denominator)
      p = (f1 - ratio)
      return p
    end

    def many_draws_choice(min_size, max_size, has_max)
      fixed = (min_size == max_size)
      bounded_and_fixed = (has_max && fixed)
      varies = (!bounded_and_fixed)
      return varies
    end

    def many_forced_value(force_stop, count, min_size, max_size, has_max, p_continue)
      true_ = true
      false_ = false
      if force_stop
        stop = false_
        return stop
      end
      below_minimum = (count < min_size)
      if below_minimum
        go_ = true_
        return go_
      end
      if has_max
        at_maximum = (count >= max_size)
        if at_maximum
          stop = false_
          return stop
        end
      end
      f0 = 0.to_f
      f1 = 1.to_f
      never = (p_continue <= f0)
      if never
        stop = false_
        return stop
      end
      always = (p_continue >= f1)
      if always
        go_ = true_
        return go_
      end
      free = nil
      return free
    end

    def filter_retry_allowed(attempts)
      u3 = 3
      allowed = (attempts < u3)
      return allowed
    end

    def many_rejection_budget(count)
      i0 = 0
      u2 = 2
      u3 = 3
      u_max = 18446744073709551615
      half_max = 9223372036854775807
      zero = i0
      accepted = zero
      positive = (count > i0)
      if positive
        accepted = count
      end
      magnitude = (accepted & MASK)
      ceiling = u_max
      doubled = ceiling
      fits = (magnitude <= half_max)
      if fits
        doubled = ((magnitude * u2) & MASK)
      end
      budget = doubled
      below_floor = (doubled < u3)
      if below_floor
        budget = u3
      end
      return budget
    end

    def many_reject_action(rejections, count, min_size)
      retry_ = 0
      stop = 1
      invalid = 2
      budget = many_rejection_budget(count)
      over_budget = (rejections > budget)
      within_budget = (!over_budget)
      if within_budget
        return retry_
      end
      below_minimum = (count < min_size)
      if below_minimum
        return invalid
      end
      return stop
    end

    def replay_integer(stream, offset, min_value, max_value, target)
      entry = deserialize_integer_choice(stream, offset)
      present = !entry.nil?
      if present
        recorded = entry
        usable = integer_validate(min_value, max_value, recorded)
        if usable
          return recorded
        end
      end
      punned = integer_unit(min_value, max_value, target)
      return punned
    end

    def replay_boolean(stream, offset)
      entry = deserialize_boolean_choice(stream, offset)
      present = !entry.nil?
      if present
        recorded = entry
        return recorded
      end
      punned = true
      return punned
    end

    def replay_float(stream, offset, min_value, max_value, allow_nan, allow_infinity, smallest_nonzero)
      entry = deserialize_float_choice(stream, offset)
      present = !entry.nil?
      if present
        recorded = entry
        usable = float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, recorded)
        if usable
          found = recorded
          return found
        end
      end
      punned = float_unit(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero)
      return punned
    end

    def replay_bytes(stream, offset, min_size, max_size)
      entry = deserialize_bytes_choice(stream, offset)
      present = !entry.nil?
      if present
        recorded = entry
        usable = bytes_validate(min_size, max_size, recorded)
        if usable
          return recorded
        end
      end
      punned = bytes_unit(min_size, max_size)
      return punned
    end

    def replay_string(stream, offset, alphabet, min_size, max_size)
      entry = deserialize_string_choice(stream, offset)
      present = !entry.nil?
      if present
        recorded = entry
        usable = string_validate(alphabet, min_size, max_size, recorded)
        if usable
          return recorded
        end
      end
      punned = string_unit(alphabet, min_size, max_size)
      return punned
    end

    def replay_integer_puns(stream, offset, min_value, max_value)
      false_ = false
      true_ = true
      entry = deserialize_integer_choice(stream, offset)
      present = !entry.nil?
      if present
        recorded = entry
        usable = integer_validate(min_value, max_value, recorded)
        if usable
          return false_
        end
      end
      return true_
    end

    def replay_boolean_puns(stream, offset)
      entry = deserialize_boolean_choice(stream, offset)
      present = !entry.nil?
      punned = (!present)
      return punned
    end

    def replay_float_puns(stream, offset, min_value, max_value, allow_nan, allow_infinity, smallest_nonzero)
      false_ = false
      true_ = true
      entry = deserialize_float_choice(stream, offset)
      present = !entry.nil?
      if present
        recorded = entry
        usable = float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, recorded)
        if usable
          return false_
        end
      end
      return true_
    end

    def replay_bytes_puns(stream, offset, min_size, max_size)
      false_ = false
      true_ = true
      entry = deserialize_bytes_choice(stream, offset)
      present = !entry.nil?
      if present
        recorded = entry
        usable = bytes_validate(min_size, max_size, recorded)
        if usable
          return false_
        end
      end
      return true_
    end

    def replay_string_puns(stream, offset, alphabet, min_size, max_size)
      false_ = false
      true_ = true
      entry = deserialize_string_choice(stream, offset)
      present = !entry.nil?
      if present
        recorded = entry
        usable = string_validate(alphabet, min_size, max_size, recorded)
        if usable
          return false_
        end
      end
      return true_
    end

    def key_append_int(encoded, value_raw)
      tag = 0
      out = String.new(encoding: Encoding::BINARY)
      out << (tag & 0xff)
      value = canonicalize_signed_le(value_raw)
      length_i64 = value.bytesize
      length = (length_i64 & MASK)
      length_bytes = u32_to_le(length)
      with_length = append_bytes(out, length_bytes)
      component = append_bytes(with_length, value)
      result = append_bytes(encoded, component)
      return result
    end

    def key_append_text(encoded, value)
      tag = 1
      out = String.new(encoding: Encoding::BINARY)
      out << (tag & 0xff)
      length_i64 = value.bytesize
      length = (length_i64 & MASK)
      length_bytes = u32_to_le(length)
      with_length = append_bytes(out, length_bytes)
      component = append_bytes(with_length, value)
      result = append_bytes(encoded, component)
      return result
    end

    def key_hash(encoded)
      i0 = 0
      i1 = 1
      u0 = 0
      u1 = 1
      offset_basis = 14695981039346656037
      prime = 1099511628211
      length = encoded.bytesize
      hash = offset_basis
      pos = i0
      loop do
        done = (pos >= length)
        if done
          break
        end
        byte_ = encoded.getbyte(pos)
        hash = (hash ^ byte_)
        hash = ((hash * prime) & MASK)
        pos = (pos + i1)
      end
      reserved = (hash == u0)
      if reserved
        return u1
      end
      return hash
    end

    def targeting_schedule_step(max_test_cases)
      u1 = 1
      u10 = 10
      u50 = 50
      ten = u64_to_bigint_le(u10)
      max_big = u64_to_bigint_le(max_test_cases)
      tenth_big = positive_div_le_nonzero(max_big, ten)
      tenth_opt = bigint_to_u64_le(tenth_big)
      tenth = tenth_opt
      cap_ = tenth
      over_fifty = (cap_ > u50)
      if over_fifty
        cap_ = u50
      end
      half = (max_test_cases >> u1)
      step = ((cap_ + u1) & MASK)
      half_wins = (half > step)
      if half_wins
        step = half
      end
      below_floor = (step < u10)
      if below_floor
        step = u10
      end
      return step
    end

    def targeting_should_fire(valid, next_at)
      fire = (valid >= next_at)
      return fire
    end

    def targeting_next_threshold(next_at, step)
      max = 18446744073709551615
      room = ((max - step) & MASK)
      overflows = (next_at > room)
      if overflows
        return max
      end
      sum = ((next_at + step) & MASK)
      return sum
    end

    def targeting_trial_budget(max_test_cases)
      u10 = 10
      max = 18446744073709551615
      room = 1844674407370955161
      overflows = (max_test_cases > room)
      if overflows
        return max
      end
      budget = ((max_test_cases * u10) & MASK)
      return budget
    end

    def targeting_improvement_allowance(round)
      u10 = 10
      u61 = 61
      max = 18446744073709551615
      too_far = (round >= u61)
      if too_far
        return max
      end
      allowance = ((u10 << round) & MASK)
      return allowance
    end

    def targeting_record(has_best, best_score, score)
      true_ = true
      none_yet = (!has_best)
      if none_yet
        return true_
      end
      improves = (score > best_score)
      return improves
    end

    def targeting_accept(new_score, current_score, new_count, current_count)
      reject = 0
      lateral = 1
      improvement = 2
      worse = (new_score < current_score)
      if worse
        return reject
      end
      strict = (new_score > current_score)
      if strict
        return improvement
      end
      grew = (new_count > current_count)
      if grew
        return reject
      end
      return lateral
    end

    def targeting_step_cap()
      cap_ = 1048576
      return cap_
    end

    def signed_le_from_i64(value)
      i0 = 0
      negative = (value < i0)
      if negative
        negated = (i0 - value)
        negated_u = (negated & MASK)
        magnitude = u64_to_bigint_le(negated_u)
        out = signed_negate_le(magnitude)
        return out
      end
      value_u = (value & MASK)
      out_pos = u64_to_bigint_le(value_u)
      return out_pos
    end

    def targeting_step_integer(min_value, max_value, value, delta)
      delta_big = signed_le_from_i64(delta)
      stepped = signed_add_le(value, delta_big)
      valid = integer_validate(min_value, max_value, stepped)
      if valid
        out = stepped.dup
        return out
      end
      none = nil
      return none
    end

    def targeting_step_boolean(value, delta)
      i0 = 0
      i1 = 1
      false_ = false
      true_ = true
      is_zero = (delta == i0)
      if is_zero
        same = value
        return same
      end
      negative = (delta < i0)
      if negative
        magnitude = (i0 - delta)
        is_down = (magnitude == i1)
        if is_down
          down = false_
          return down
        end
        none_down = nil
        return none_down
      end
      is_up = (delta == i1)
      if is_up
        up = true_
        return up
      end
      none = nil
      return none
    end

    def targeting_step_float(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, value, delta)
      i0 = 0
      negative = (delta < i0)
      magnitude_i = delta
      if negative
        magnitude_i = (i0 - delta)
      end
      magnitude_u = (magnitude_i & MASK)
      delta_f = magnitude_u.to_f
      if negative
        delta_f = f64_neg(delta_f)
      end
      stepped = (value + delta_f)
      valid = float_validate(min_value, max_value, allow_nan, allow_infinity, smallest_nonzero, stepped)
      if valid
        out = stepped
        return out
      end
      none = nil
      return none
    end

    def targeting_step_bytes(min_size, max_size, value, delta)
      i0 = 0
      i1 = 1
      u0 = 0
      n = value.bytesize
      le = String.new(encoding: Encoding::BINARY)
      pos = n
      loop do
        at_start = (pos <= i0)
        if at_start
          break
        end
        pos = (pos - i1)
        byte_ = value.getbyte(pos)
        le << (byte_ & 0xff)
      end
      le << (u0 & 0xff)
      delta_big = signed_le_from_i64(delta)
      sum = signed_add_le(le, delta_big)
      zero = bigint_zero()
      sign = signed_compare_le(sum, zero)
      negative = (sign < i0)
      if negative
        none_negative = nil
        return none_negative
      end
      sum_len = sum.bytesize
      mag_len = sum_len
      loop do
        empty = (mag_len <= i0)
        if empty
          break
        end
        last_at = (mag_len - i1)
        last = sum.getbyte(last_at)
        nonzero = (last != u0)
        if nonzero
          break
        end
        mag_len = last_at
      end
      width = mag_len
      narrow = (width < n)
      if narrow
        width = n
      end
      out = String.new(encoding: Encoding::BINARY)
      at = width
      loop do
        done = (at <= i0)
        if done
          break
        end
        at = (at - i1)
        in_magnitude = (at < mag_len)
        digit = u0
        if in_magnitude
          digit = sum.getbyte(at)
        end
        out << (digit & 0xff)
      end
      valid = bytes_validate(min_size, max_size, out)
      if valid
        some = out.dup
        return some
      end
      none = nil
      return none
    end

    def find_integer_probe(mode, a, b)
      u1 = 1
      u2 = 2
      u3 = 3
      done = (mode >= u3)
      if done
        none = nil
        return none
      end
      linear = (mode < u1)
      if linear
        probe_a = a
        return probe_a
      end
      grow = (mode < u2)
      if grow
        probe_b = b
        return probe_b
      end
      gap = ((b - a) & MASK)
      half = (gap >> u1)
      mid = ((a + half) & MASK)
      probe_mid = mid
      return probe_mid
    end

    def find_integer_result(mode, a, b)
      u3 = 3
      done = (mode >= u3)
      if done
        answer = a
        return answer
      end
      none = nil
      return none
    end

    def find_integer_bracket_mode(lo, hi)
      u1 = 1
      u2 = 2
      u3 = 3
      next_ = ((lo + u1) & MASK)
      open = (next_ < hi)
      if open
        return u2
      end
      return u3
    end

    def find_integer_next_mode(mode, a, b, ok)
      u0 = 0
      u1 = 1
      u2 = 2
      u3 = 3
      u4 = 4
      half_max = 9223372036854775807
      done = (mode >= u3)
      if done
        return u3
      end
      linear = (mode < u1)
      if linear
        failed = (!ok)
        if failed
          return u3
        end
        still_small = (a < u4)
        if still_small
          return u0
        end
        return u1
      end
      grow = (mode < u2)
      if grow
        if ok
          overflows = (b > half_max)
          if overflows
            return u3
          end
          return u1
        end
        bracketed = find_integer_bracket_mode(a, b)
        return bracketed
      end
      gap = ((b - a) & MASK)
      half = (gap >> u1)
      mid = ((a + half) & MASK)
      if ok
        above = find_integer_bracket_mode(mid, b)
        return above
      end
      below = find_integer_bracket_mode(a, mid)
      return below
    end

    def find_integer_next_a(mode, a, b, ok)
      u1 = 1
      u2 = 2
      u3 = 3
      u4 = 4
      done = (mode >= u3)
      if done
        return a
      end
      linear = (mode < u1)
      if linear
        failed = (!ok)
        if failed
          previous = ((a - u1) & MASK)
          return previous
        end
        still_small = (a < u4)
        if still_small
          next_ = ((a + u1) & MASK)
          return next_
        end
        return u4
      end
      grow = (mode < u2)
      if grow
        if ok
          return b
        end
        return a
      end
      if ok
        gap = ((b - a) & MASK)
        half = (gap >> u1)
        mid = ((a + half) & MASK)
        return mid
      end
      return a
    end

    def find_integer_next_b(mode, a, b, ok)
      u1 = 1
      u2 = 2
      u3 = 3
      u4 = 4
      u5 = 5
      half_max = 9223372036854775807
      done = (mode >= u3)
      if done
        return b
      end
      linear = (mode < u1)
      if linear
        failed = (!ok)
        if failed
          return b
        end
        still_small = (a < u4)
        if still_small
          return b
        end
        return u5
      end
      grow = (mode < u2)
      if grow
        if ok
          overflows = (b > half_max)
          if overflows
            return b
          end
          doubled = ((b * u2) & MASK)
          return doubled
        end
        return b
      end
      if ok
        return b
      end
      gap = ((b - a) & MASK)
      half = (gap >> u1)
      mid = ((a + half) & MASK)
      return mid
    end

    def recursive_large_target_probability()
      probability = 0.75.to_f
      return probability
    end

    def recursive_target_drawn(max_leaves)
      u2 = 2
      drawn = (max_leaves >= u2)
      return drawn
    end

    def recursive_retry_allowed(attempt)
      u9 = 9
      allowed = (attempt < u9)
      return allowed
    end

    def recursive_effective_target(target, attempt)
      u1 = 1
      shifted = (target >> attempt)
      below_one = (shifted < u1)
      if below_one
        return u1
      end
      return shifted
    end

    def recursive_arity_estimate(closed_children, closed_branches)
      prior_children = 0.5.to_f
      prior_branches = 0.25.to_f
      children = closed_children.to_f
      branches = closed_branches.to_f
      numerator = (prior_children + children)
      denominator = (prior_branches + branches)
      estimate = (numerator / denominator)
      return estimate
    end

    def recursive_branch_probability(mean_arity, max_leaves)
      f1 = 1.to_f
      f0_95 = 0.95.to_f
      u2 = 2
      u4294967296 = 4294967296
      arity = mean_arity
      arity_too_small = (arity < f1)
      if arity_too_small
        arity = f1
      end
      budget = max_leaves
      budget_too_small = (budget < u2)
      if budget_too_small
        budget = u2
      end
      budget_too_large = (budget > u4294967296)
      if budget_too_large
        budget = u4294967296
      end
      budget_f = budget.to_f
      numerator = (budget_f - f1)
      scaled_arity = (budget_f * arity)
      denominator = (scaled_arity - f1)
      probability = (numerator / denominator)
      over_cap = (probability > f0_95)
      if over_cap
        return f0_95
      end
      return probability
    end

    def recursive_priced_probability(closed_children, closed_branches, attempt, target)
      arity = recursive_arity_estimate(closed_children, closed_branches)
      attempt_f = attempt.to_f
      priced_arity = (arity + attempt_f)
      effective = recursive_effective_target(target, attempt)
      probability = recursive_branch_probability(priced_arity, effective)
      return probability
    end

    def recursive_profile_boundary(target, arity, tail_probability, max_depth)
      u0 = 0
      u1 = 1
      u4096 = 4096
      f1 = 1.to_f
      grow = 0.95.to_f
      horizon = max_depth
      too_far = (horizon > u4096)
      if too_far
        horizon = u4096
      end
      tail_numerator = (f1 - tail_probability)
      tail_times_arity = (tail_probability * arity)
      tail_denominator = (f1 - tail_times_arity)
      lo = (tail_numerator / tail_denominator)
      grow_times_arity = (grow * arity)
      grow_stop = (f1 - grow)
      lift = (grow_times_arity * lo)
      hi = (grow_stop + lift)
      boundary = u0
      loop do
        reached = (hi >= target)
        at_horizon = (boundary >= horizon)
        done = (reached || at_horizon)
        if done
          break
        end
        next_lift = (grow_times_arity * hi)
        next_ = (grow_stop + next_lift)
        gain = (next_ - hi)
        epsilon = 0.000000001.to_f
        plateau = (gain < epsilon)
        if plateau
          break
        end
        lo_lift = (grow_times_arity * lo)
        lo = (grow_stop + lo_lift)
        hi = next_
        boundary = ((boundary + u1) & MASK)
      end
      return boundary
    end

    def recursive_profile_expected(target, arity, tail_probability, max_depth)
      u0 = 0
      u1 = 1
      f1 = 1.to_f
      grow = 0.95.to_f
      zero_depth = (max_depth == u0)
      if zero_depth
        return f1
      end
      boundary = recursive_profile_boundary(target, arity, tail_probability, max_depth)
      tail_numerator = (f1 - tail_probability)
      tail_times_arity = (tail_probability * arity)
      tail_denominator = (f1 - tail_times_arity)
      lo = (tail_numerator / tail_denominator)
      grow_times_arity = (grow * arity)
      grow_stop = (f1 - grow)
      lo_lift = (grow_times_arity * lo)
      hi = (grow_stop + lo_lift)
      at = u0
      loop do
        done = (at >= boundary)
        if done
          break
        end
        next_lo_lift = (grow_times_arity * lo)
        lo = (grow_stop + next_lo_lift)
        next_hi_lift = (grow_times_arity * hi)
        hi = (grow_stop + next_hi_lift)
        at = ((at + u1) & MASK)
      end
      hi_below = (hi <= target)
      if hi_below
        return hi
      end
      lo_above = (lo >= target)
      if lo_above
        return lo
      end
      return target
    end

    def recursive_decision_probability(max_depth, depth, target, attempt, closed_children, closed_branches)
      f0 = 0.to_f
      u1 = 1
      at_cap = (depth >= max_depth)
      if at_cap
        return f0
      end
      effective = recursive_effective_target(target, attempt)
      single = (effective == u1)
      if single
        priced = recursive_priced_probability(closed_children, closed_branches, attempt, target)
        return priced
      end
      arity = recursive_arity_estimate(closed_children, closed_branches)
      attempt_f = attempt.to_f
      priced_arity = (arity + attempt_f)
      u2 = 2
      tail = recursive_branch_probability(priced_arity, u2)
      target_f = effective.to_f
      boundary = recursive_profile_boundary(target_f, arity, tail, max_depth)
      before = (depth < boundary)
      if before
        grow = 0.95.to_f
        return grow
      end
      on_boundary = (depth == boundary)
      if on_boundary
        f1 = 1.to_f
        grow = 0.95.to_f
        tail_numerator = (f1 - tail)
        tail_times_arity = (tail * arity)
        tail_denominator = (f1 - tail_times_arity)
        lo = (tail_numerator / tail_denominator)
        grow_times_arity = (grow * arity)
        grow_stop = (f1 - grow)
        lo_lift = (grow_times_arity * lo)
        hi = (grow_stop + lo_lift)
        at = 0
        loop do
          done = (at >= boundary)
          if done
            break
          end
          next_lo_lift = (grow_times_arity * lo)
          lo = (grow_stop + next_lo_lift)
          next_hi_lift = (grow_times_arity * hi)
          hi = (grow_stop + next_hi_lift)
          at = ((at + u1) & MASK)
        end
        hi_below = (hi <= target_f)
        if hi_below
          return grow
        end
        lo_above = (lo >= target_f)
        if lo_above
          return tail
        end
        gap = (hi - lo)
        offset = (target_f - lo)
        fraction = (offset / gap)
        probability_gap = (grow - tail)
        scaled = (probability_gap * fraction)
        interpolated = (tail + scaled)
        return interpolated
      end
      return tail
    end

    def recursive_finish_mispriced(max_depth, target, attempt, leaves, closed_children, closed_branches, start_probability, reprices)
      u1 = 1
      u2 = 2
      maxed = (reprices >= u2)
      if maxed
        false_ = false
        return false_
      end
      effective = recursive_effective_target(target, attempt)
      single = (effective == u1)
      if single
        repriced = recursive_priced_probability(closed_children, closed_branches, attempt, target)
        difference = (repriced - start_probability)
        threshold = 0.05.to_f
        mispriced = (difference > threshold)
        return mispriced
      end
      half_floor = (effective >> u1)
      remainder = (effective & u1)
      half_ceil = ((half_floor + remainder) & MASK)
      too_small = (leaves < half_ceil)
      if too_small
        arity = recursive_arity_estimate(closed_children, closed_branches)
        target_f = effective.to_f
        zero = 0.to_f
        reachable = recursive_profile_expected(target_f, arity, zero, max_depth)
        f2 = 2.to_f
        twice_reachable = (reachable * f2)
        reachable_enough = (twice_reachable >= target_f)
        return reachable_enough
      end
      false_ = false
      return false_
    end
  end
end
