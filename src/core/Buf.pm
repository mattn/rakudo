my role Buf[::T = int8] does Positional[T] does Stringy is repr('VMArray') is array_type(T) {
    proto method new(|) { * }
    multi method new() {
        nqp::create(self)
    }
    multi method new(@values) {
        my $buf := nqp::create(self);
        my int $n = @values.elems;
        my int $i;
        nqp::setelems($buf, $n);
        while $i < $n {
            nqp::bindpos_i($buf, $i, @values.at_pos($i));
            $i = $i + 1;
        }
        $buf
    }
    multi method new(*@values) {
        self.new(@values)
    }
    
    multi method at_pos(Buf:D: $i) {
        nqp::atpos_i(self, $i.Int)
    }
    multi method at_pos(Buf:D: Int $i) {
        nqp::atpos_i(self, $i)
    }
    multi method at_pos(Buf:D: int $i) {
        nqp::atpos_i(self, $i)
    }
    
    multi method Bool(Buf:D:) {
        nqp::p6bool(nqp::elems(self));
    }

    method elems(Buf:D:) {
        nqp::p6box_i(nqp::elems(self));
    }
    method bytes(Buf:D:) {
        self.elems
    }
    method chars()       { X::Buf::AsStr.new(method => 'chars').throw }
    multi method Str()   { X::Buf::AsStr.new(method => 'Str'  ).throw }

    method Numeric { self.elems }
    method Int     { self.elems }
    
    method list() {
        my @l;
        my int $n = nqp::elems(self);
        my int $i = 0;
        while $i < $n {
            @l[$i] = nqp::atpos_i(self, $i);
            $i = $i + 1;
        }
        @l;
    }

    multi method gist(Buf:D:) {
        'Buf:0x<' ~ self.list.fmt('%02x', ' ') ~ '>'
    }
    multi method perl(Buf:D:) {
        self.^name ~ '.new(' ~ self.list.join(', ') ~ ')';
    }
    
    method subbuf(Buf:D: $from = 0, $len = self.elems - $from) {
        my $ret := nqp::create(self);
        my int $llen = $len.Int;
        nqp::setelems($ret, $llen);
        my int $i = 0;
        my int $f = $from.Int;
        while $i < $llen {
            nqp::bindpos_i($ret, $i, nqp::atpos_i(self, $f));
            $i = $i + 1;
            $f = $f + 1;
        }
        $ret
    }
    
    method unpack(Buf:D: $template) {
        my @bytes = self.list;
        my @fields;
        for $template.comb(/<[a..zA..Z]>[\d+|'*']?/) -> $unit {
            my $directive = $unit.substr(0, 1);
            my $amount = $unit.substr(1);

            given $directive {
                when 'A' {
                    my $asciistring;
                    if $amount eq '*' {
                        $amount = @bytes.elems;
                    }
                    for ^$amount {
                        $asciistring ~= chr(shift @bytes);
                    }
                    @fields.push($asciistring);
                }
                when 'H' {
                    my $hexstring;
                    while @bytes {
                        my $byte = shift @bytes;
                        $hexstring ~= ($byte +> 4).fmt('%x')
                                    ~ ($byte % 16).fmt('%x');
                    }
                    @fields.push($hexstring);
                }
                when 'x' {
                    if $amount eq '*' {
                        $amount = 0;
                    }
                    elsif $amount eq '' {
                        $amount = 1;
                    }
                    splice @bytes, 0, $amount;
                }
                when 'C' {
                    @fields.push: shift @bytes;
                }
                when 'S' | 'v' {
                    @fields.push: shift(@bytes)
                                 + (shift(@bytes) +< 0x08);
                }
                when 'L' | 'V' {
                    @fields.push: shift(@bytes)
                                 + (shift(@bytes) +< 0x08)
                                 + (shift(@bytes) +< 0x10)
                                 + (shift(@bytes) +< 0x18);
                }
                when 'n' {
                    @fields.push: (shift(@bytes) +< 0x08)
                                 + shift(@bytes);
                }
                when 'N' {
                    @fields.push: (shift(@bytes) +< 0x18)
                                 + (shift(@bytes) +< 0x10)
                                 + (shift(@bytes) +< 0x08)
                                 + shift(@bytes);
                }
                X::Buf::Pack.new(:$directive).throw;
            }
        }

        return |@fields;
    }

    # XXX: the pack.t spectest file seems to require this method
    # not sure if it should be changed to list there...
    method contents(Buf:D:) { self.list }
}

constant buf8 = Buf[int8];
constant buf16 = Buf[int16];
constant buf32 = Buf[int32];
constant buf64 = Buf[int64];

multi sub pack(Str $template, *@items) {
    my @bytes;
    for $template.comb(/<[a..zA..Z]>[\d+|'*']?/) -> $unit {
        my $directive = $unit.substr(0, 1);
        my $amount = $unit.substr(1);

        given $directive {
            when 'A' {
                my $ascii = shift @items // '';
                for $ascii.comb -> $char {
                    X::Buf::Pack::NonASCII.new(:$char).throw if ord($char) > 0x7f;
                    @bytes.push: ord($char);
                }
                if $amount ne '*' {
                    @bytes.push: 0x20 xx ($amount - $ascii.chars);
                }
            }
            when 'H' {
                my $hexstring = shift @items // '';
                if $hexstring % 2 {
                    $hexstring ~= '0';
                }
                @bytes.push: map { :16($_) }, $hexstring.comb(/../);
            }
            when 'x' {
                if $amount eq '*' {
                    $amount = 0;
                }
                elsif $amount eq '' {
                    $amount = 1;
                }
                @bytes.push: 0x00 xx $amount;
            }
            when 'C' {
                my $number = shift(@items);
                @bytes.push: $number % 0x100;
            }
            when 'S' | 'v' {
                my $number = shift(@items);
                @bytes.push: ($number, $number +> 0x08) >>%>> 0x100;
            }
            when 'L' | 'V' {
                my $number = shift(@items);
                @bytes.push: ($number, $number +> 0x08,
                              $number +> 0x10, $number +> 0x18) >>%>> 0x100;
            }
            when 'n' {
                my $number = shift(@items);
                @bytes.push: ($number +> 0x08, $number) >>%>> 0x100;
            }
            when 'N' {
                my $number = shift(@items);
                @bytes.push: ($number +> 0x18, $number +> 0x10,
                              $number +> 0x08, $number) >>%>> 0x100;
            }
            X::Buf::Pack.new(:$directive).throw;
        }
    }

    return Buf.new(@bytes);
}
