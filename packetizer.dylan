module: packetizer
Author:    Andreas Bogk, Hannes Mehnert
Copyright: (C) 2005, 2006,  All rights reserved. Free for non-commercial use.


define class <malformed-packet-error> (<error>)
end;

define class <alignment-error> (<error>)
end;

define class <unknown-at-compile-time> (<number>)
end;

define constant $unknown-at-compile-time = make(<unknown-at-compile-time>);
define sealed domain \+ (<number>, <unknown-at-compile-time>);
define sealed domain \+ (<unknown-at-compile-time>, <number>);
define sealed domain \+ (<unknown-at-compile-time>, <unknown-at-compile-time>);

define method \+ (a :: <number>, b :: <unknown-at-compile-time>)
 => (res :: <number>)
  b
end;

define method \+ (a :: <unknown-at-compile-time>, b :: <number>)
 => (res :: <number>)
  a
end;

define method \+ (a :: <unknown-at-compile-time>, b :: <unknown-at-compile-time>)
 => (res :: <number>)
  a
end;

define constant <byte-sequence> = <byte-vector-subsequence>;

define abstract class <frame> (<object>)
end;

define generic parse-frame
  (frame-type :: subclass (<frame>),
   packet :: <sequence>,
   #rest rest, #key, #all-keys)
 => (value :: <object>, next-unparsed :: <integer>);

define method parse-frame
  (frame-type :: subclass (<frame>),
   packet :: <byte-vector>,
   #rest rest,
   #key, #all-keys)
 => (value :: <object>, next-unparsed :: <integer>);
 let packet-subseq = subsequence(packet);
 apply(parse-frame, frame-type, packet-subseq, rest);
end;

define generic assemble-frame-into (frame :: <frame>,
                                    packet :: <byte-vector>,
                                    start :: <integer>);

define generic assemble-frame
  (frame :: <frame>) => (packet :: <vector>);

define generic assemble-frame-as
    (frame-type :: subclass(<frame>), data :: <object>) => (packet :: <vector>);

define method assemble-frame-as
    (frame-type :: subclass(<frame>), data :: <object>) => (packet :: <byte-vector>);
  if (instance?(data, frame-type))
    assemble-frame(data)
  else
    error("Don't know how to convert representation!")
  end
end;

define generic print-frame (frame :: <frame>, stream :: <stream>) => ();

define method print-frame (frame :: <frame>, stream :: <stream>) => ();
  write(stream, as(<string>, frame))
end;

define generic high-level-type (low-level-type :: subclass(<frame>)) => (res :: <type>);
define sealed domain high-level-type (subclass(<frame>));

define inline method high-level-type (object :: subclass(<frame>)) => (res :: <type>)
  object
end;

define generic frame-fields (frame :: type-union(<container-frame>,
                                                 subclass(<container-frame>)))
  => (fields :: <sequence>);

define inline method frame-fields (frame :: subclass(<container-frame>)) => (fields :: <list>)
  #()
end;

define inline method frame-fields (frame :: <container-frame>) => (fields :: <list>)
  frame-fields(frame.object-class);
end;

define method fixup!(frame :: <container-frame>,
                     packet :: type-union(<byte-vector>, <byte-vector-subsequence>))
end;

define generic frame-size (frame :: type-union(<frame>, subclass(<fixed-size-frame>)))
 => (length :: <integer>);

define generic field-size (frame :: subclass(<frame>))
 => (length :: <number>);

define inline method field-size (frame :: subclass(<frame>))
 => (length :: <unknown-at-compile-time>)
  $unknown-at-compile-time;
end;

define method summary (frame :: <frame>) => (summary :: <string>)
  format-to-string("%=", frame.object-class);
end;

define abstract class <leaf-frame> (<frame>)
end;

define method print-object (object :: <leaf-frame>, stream :: <stream>) => ()
  write(stream, as(<string>, object));
end;

define abstract class <fixed-size-frame> (<frame>)
end;

define inline method frame-size (frame :: subclass(<fixed-size-frame>))
 => (length :: <integer>)
  field-size(frame);
end;

define inline method frame-size (frame :: <fixed-size-frame>)
 => (length :: <integer>)
  field-size(frame.object-class);
end;

define abstract class <variable-size-frame> (<frame>)
end;

define abstract class <untranslated-frame> (<frame>)
end;

define abstract class <translated-frame> (<frame>)
end;

define abstract class <fixed-size-untranslated-frame>
    (<fixed-size-frame>, <untranslated-frame>)
end;

define abstract class <variable-size-untranslated-frame>
    (<variable-size-frame>, <untranslated-frame>)
end;

define abstract class <fixed-size-untranslated-leaf-frame>
    (<leaf-frame>, <fixed-size-untranslated-frame>)
end;

define abstract class <variable-size-untranslated-leaf-frame>
    (<leaf-frame>, <variable-size-untranslated-frame>)
end;

define abstract class <fixed-size-translated-leaf-frame>
    (<leaf-frame>, <fixed-size-frame>, <translated-frame>)
end;

define abstract class <variable-size-translated-leaf-frame>
    (<leaf-frame>, <variable-size-frame>, <translated-frame>)
end;

define generic read-frame
  (frame-type :: subclass(<leaf-frame>), stream :: <stream>) => (frame :: <leaf-frame>);

define abstract class <container-frame> (<variable-size-untranslated-frame>)
  virtual constant slot name :: <string>;
  slot parent :: false-or(<container-frame>) = #f, init-keyword: parent:;
  constant slot concrete-frame-fields :: false-or(<collection>) = #f,
    init-keyword: frame-fields:;
end;

define method name(frame :: <container-frame>)
  "anonymous"
end;

define method field-size (frame :: subclass(<container-frame>)) => (res :: <number>)
  reduce1(\+, map(method(x) if ((instance?(x, <statically-typed-field>)) & subtype?(x.type, <fixed-size-frame>))
                              field-size(x.type)
                            else
                              $unknown-at-compile-time
                            end
                          end, frame-fields(frame)))
end;

define method frame-size (frame :: <container-frame>) => (res :: <integer>)
  reduce1(\+, map(curry(get-field-size-aux, frame), frame.frame-fields));
end;

define method parse-frame (frame-type :: subclass(<container-frame>),
                           packet :: <byte-vector-subsequence>,
                           #key start :: <integer> = 0,
                           parent :: false-or(<container-frame>) = #f)
 => (frame :: <container-frame>, next-unparsed :: <integer>);
  let res = make(unparsed-class(frame-type),
                 packet: subsequence(packet, start: byte-offset(start)),
                 parent: parent);
  let args = make(<stretchy-vector>);
  let concrete-frame-fields = make(<stretchy-vector>);
  for (field in frame-fields(res),
       i from 0)
    let type = get-frame-type(field, res);
    let end-of-field = start + field-size(type);
    if (end-of-field = $unknown-at-compile-time)
      if (field.end-offset)
        end-of-field := field.end-offset(res);
      elseif (field.length)
        end-of-field := start + field.length(res);
      elseif (i + 1 < frame-fields(res).size)
        //search for next fixed or computable start-offset-field
        if (frame-fields(res)[i + 1].start-offset)
          end-of-field := frame-fields(res)[i + 1].start-offset(res);
        end;
      end;
    end;

    //hexdump(*standard-output*, packet);
    //format-out("field %s start %d end %=\n", field.name, start, end-of-field);
    let (value, offset) =
      parse-frame-aux(field,
                      type,
                      bit-offset(start),
                      subsequence(packet,
                                  start: byte-offset(start),
                                  end: if ((end-of-field ~= $unknown-at-compile-time) &
                                           (byte-offset(end-of-field + 7) < packet.size))
                                         byte-offset(end-of-field + 7)
                                       else
                                         packet.size
                                       end),
                      res);

    concrete-frame-fields := add!(concrete-frame-fields, 
                                  make(<frame-field>,
                                       start: start,
                                       end: offset,
                                       frame: value,
                                       field: field,
                                       length: offset - start));
    start := byte-offset(start) * 8 + offset;

    if (end-of-field ~= $unknown-at-compile-time)
      unless (start = end-of-field)
        //format-out("found a gap, start: %d (%d Bytes), end: %d (%d Bytes)\n", start, byte-offset(start),
        //           end-of-field, byte-offset(end-of-field));
        start := end-of-field;
      end;
    end;

    args := add!(args, field.name);
    args := add!(args, value);
  end;
  args := add!(args, #"frame-fields");
  args := add!(args, concrete-frame-fields);
  let decoded-frame = apply(make, decoded-class(frame-type), args);
  fixup-parent(decoded-frame, parent);
  values(decoded-frame, start);
end;


define method fixup-parent (frame :: <container-frame>,
                            parent-frame :: false-or(<container-frame>)) => ()
  frame.parent := parent-frame;
  for (field in frame-fields(frame))
    let subframe = field.getter(frame);
    if (instance?(subframe, <container-frame>))
      fixup-parent(subframe, frame);
    end;
  end;
end;

define method parse-frame-aux (field :: <single-field>,
                               frame-type :: subclass(<frame>),
                               start :: <integer>,
                               packet :: <byte-sequence>,
                               parent :: false-or(<container-frame>))
  parse-frame(frame-type, packet, start: start, parent: parent);
end;

define method parse-frame-aux (field :: <variably-typed-field>,
                               frame-type :: subclass(<frame>),
                               start :: <integer>,
                               packet :: <byte-sequence>,
                               parent :: false-or(<container-frame>))
  parse-frame(frame-type, packet, start: start, parent: parent);
end;

define method parse-frame-aux (field :: <self-delimited-repeated-field>,
                               frame-type :: subclass(<frame>),
                               start :: <integer>,
                               packet :: <byte-sequence>,
                               parent :: false-or(<container-frame>))
  let res = make(<stretchy-vector>);
  let start = start;
  if (packet.size > 0)
    let (value, offset) = parse-frame(frame-type, packet, start: start, parent: parent);
    res := add!(res, value);
    start := offset;
    while ((~ field.reached-end?(res.last)) & (byte-offset(start) < packet.size))
      let (value, offset) = parse-frame(frame-type, packet, start: start, parent: parent);
      res := add!(res, value);
      start := offset;
    end;
  end;
  values(res, start);
end;

define method parse-frame-aux (field :: <count-repeated-field>,
                               frame-type :: subclass(<frame>),
                               start :: <integer>,
                               packet :: <byte-sequence>,
                               parent :: false-or(<container-frame>))
  let res = make(<stretchy-vector>);
  let start = start;
  if (packet.size > 0)
    for (i from 0 below field.count(parent))
      let (value, offset) = parse-frame(frame-type, packet, start: start, parent: parent);
      res := add!(res, value);
      start := offset;
    end;
  end;
  values(res, start);
end;

define method assemble-frame (frame :: <container-frame>) => (packet :: <byte-vector>);
  let result = make(<byte-vector>, size: byte-offset(frame-size(frame)), fill: 0);
  assemble-frame-into(frame, result, 0);
  fixup!(frame, result);
  result;
end;

define method as(type == <string>, frame :: <container-frame>) => (string :: <string>);
  apply(concatenate,
        format-to-string("%=\n", frame.object-class),
        map(method(field :: <field>)
                           concatenate(as(<string>, field.name),
                                       ": ",
                                       as(<string>, field.getter(frame)),
                                       "\n")
                         end, frame-fields(frame)))
end;

define method assemble-frame-into (frame :: <container-frame>,
                                   packet :: <byte-vector>,
                                   start :: <integer>)
  for (field in frame-fields(frame),
       offset = start then offset + get-field-size-aux(frame, field))
    if (field.getter(frame) = #f)
      if (field.fixup-function)
        field.setter(field.fixup-function(frame), frame);
      else
        error("No value for field %s while assembling", field.name);
      end;
    end;
    assemble-field-into(field, frame, packet, offset)
  end;
end;

define method assemble-field-into(field :: <single-field>,
                                  frame :: <container-frame>,
                                  packet :: <byte-vector>,
                                  start :: <integer>)
  assemble-aux(field.type, field.getter(frame), packet, start);
end;

define method assemble-field-into(field :: <variably-typed-field>,
                                  frame :: <container-frame>,
                                  packet :: <byte-vector>,
                                  start :: <integer>)
  assemble-frame-into(field.getter(frame), packet, start);
end;

define method assemble-field-into(field :: <repeated-field>,
                                  frame :: <container-frame>,
                                  packet :: <byte-vector>,
                                  start :: <integer>)
  for (ele in field.getter(frame),
       offset = start then offset + frame-size(ele))
    assemble-frame-into(ele, packet, offset)
  end;
end;

define method assemble-aux (frame-type :: subclass(<untranslated-frame>),
                            frame :: <frame>,
                            packet :: <byte-vector>,
                            start :: <integer>)
  assemble-frame-into(frame, packet, start);
end;

define method assemble-aux (frame-type :: subclass(<translated-frame>),
                            frame :: <object>,
                            packet :: <byte-vector>,
                            start :: <integer>)
  assemble-frame-into-as(frame-type, frame, packet, start);
end;                            

define abstract class <field> (<object>)
  slot name, required-init-keyword: name:;
  slot init-value = #f, init-keyword: init:;
  slot fixup-function :: false-or(<function>) = #f, init-keyword: fixup:;
  slot getter, required-init-keyword: getter:;
  slot setter, required-init-keyword: setter:;
  slot start-offset = #f, init-keyword: start:;
  slot end-offset = #f, init-keyword: end:;
  slot length = #f, init-keyword: length:;
end;

define abstract class <fixed-position-mixin> (<object>)
  slot start-offset :: <integer>, required-init-keyword: start:;
  slot end-offset :: <integer>, required-init-keyword: end:;
end;

define abstract class <statically-typed-field> (<field>)
  slot type, required-init-keyword: type:;
end;

define class <single-field> (<statically-typed-field>)
end;

define class <variably-typed-field> (<field>)
  //type-function has to return a subclass of <container-frame>
  slot type-function, required-init-keyword: type-function:;
end;

define abstract class <repeated-field> (<statically-typed-field>)
  //only <untranslated-frames> are stored in <repeated-fields>

  //this is only temporary, it should be moved to self-delimited-repeated-field
  //slot reached-end?, required-init-keyword: reached-end?:;
end;

define class <self-delimited-repeated-field> (<repeated-field>)
  slot reached-end?, required-init-keyword: reached-end?:;
end;

define class <count-repeated-field> (<repeated-field>)
  slot count, required-init-keyword: count:;
end;

define method make(class == <repeated-field>,
                   #rest rest, 
                   #key count, reached-end?,
                   #all-keys)
 => (instance :: <repeated-field>);
  apply(make,
        if(count)
          <count-repeated-field>
        elseif(reached-end?)
          <self-delimited-repeated-field>
        else
          error("unsupported repeated field")
        end,
        count: count,
        reached-end?: reached-end?,
        rest);
end;

define abstract class <unknown-offset-field> (<field>)
end;

define abstract class <computable-offset-field> (<field>)
end;

define abstract class <fixed-offset-field> (<field>)
end;


define generic assemble-field (frame :: <frame>, field :: <field>)
 => (packet :: <vector>);

define class <frame-field> (<object>)
  constant slot frame :: <object>, required-init-keyword: frame:;
  constant slot field :: <field>, required-init-keyword: field:;
  constant slot start-offset :: <integer>, required-init-keyword: start:;
  constant slot end-offset :: <integer>, required-init-keyword: end:;
  constant slot length :: <integer>, required-init-keyword: length:;
end;

define sideways method print-object (frame-field :: <frame-field>, stream :: <stream>) => ();
  format(stream, "%s: %=", frame-field.field.name, frame-field.frame)
end;

/*
define method get-value (frame-field :: <frame-field>) => (result);
  frame-field.field.getter(frame-field.frame)
end:

define method get-frame-fields (frame :: <container-frame>) => (frame-fields :: <sequence>);
  map(method(x)
        make(<frame-field>, frame: frame, field: x)
      end,
      frame.frame-fields)
end;

define method get-field-size (frame-field :: <frame-field>) => (size);
  get-field-size-aux(frame-field.frame, frame-field.field)
end;
*/
define method get-field-size-aux (frame :: <container-frame>, field :: <statically-typed-field>)
 => (size :: <integer>)
  get-field-size-aux-aux(frame, field, field.type);
end;

define method get-field-size-aux (frame :: <container-frame>, field :: <variably-typed-field>)
 => (size :: <integer>)
  frame-size(field.getter(frame));
end;

define method get-field-size-aux (frame :: <container-frame>, field :: <repeated-field>)
  reduce(\+, 0, map(frame-size, field.getter(frame)));
end;

define method get-field-size-aux-aux (frame :: <frame>,
                                      field :: <single-field>,
                                      frame-type :: subclass(<fixed-size-frame>))
 => (res :: <integer>)
  frame-size(frame-type);
end;

define method get-field-size-aux-aux (frame :: <frame>,
                                      field :: <single-field>,
                                      frame-type :: subclass(<variable-size-untranslated-frame>))
 => (res :: <integer>)
  frame-size(field.getter(frame))
end;

define method get-field-size-aux-aux (frame :: <frame>,
                                      field :: <single-field>,
                                      frame-type :: subclass(<variable-size-translated-leaf-frame>))
 => (res :: <integer>)
  //need to look for user-defined static size method
  //or assemble frame, cache it and get its size
  error("Not yet implemented!")
end;

define method assemble-field (frame :: <frame>,
                              field :: <statically-typed-field>)
 => (packet :: <vector>)
  assemble-frame-as(field.type, field.getter(frame))
end;

define method assemble-field (frame :: <frame>,
                              field :: <variably-typed-field>)
 => (packet :: <vector>)
  assemble-frame(field.getter(frame))
end;

define method assemble-field (frame :: <frame>,
                              field :: <repeated-field>)
 => (packet :: <vector>)
  apply(concatenate, map(curry(assemble-frame-as, field.type), field.getter(frame)))
end;

define generic get-frame-type (field :: <field>, frame :: <frame>)
 => (type :: <class>);

define method get-frame-type (field :: <statically-typed-field>, frame :: <frame>)
 => (type :: <class>);
  field.type;
end;

define method get-frame-type (field :: <variably-typed-field>, frame :: <frame>)
 => (type :: <class>);
  field.type-function(frame);
end;


define class <unsigned-byte> (<fixed-size-translated-leaf-frame>)
  slot data :: <byte>, init-keyword: data:;
end;

define method parse-frame (frame-type == <unsigned-byte>,
                           packet :: <byte-sequence>,
                           #key start :: <integer> = 0)
 => (value :: <byte>, next-unparsed :: <integer>)
  byte-aligned(start);
  if (packet.size < byte-offset(start) + 1)
    signal(make(<malformed-packet-error>))
  else
    values(packet[byte-offset(start)], start + 8)
  end;
end;

define method assemble-frame-into-as
    (frame-type == <unsigned-byte>, data :: <byte>, packet :: <byte-vector>, start :: <integer>)
  byte-aligned(start);
  packet[byte-offset(start)] := data;
end;

define method as (class == <string>, frame :: <unsigned-byte>)
 => (string :: <string>)
  concatenate("0x", integer-to-string(frame.data, base: 16, size: 2));
end;

define inline method field-size (type == <unsigned-byte>)
  => (length :: <integer>)
  8
end;

define inline method high-level-type (low-level-type == <unsigned-byte>)
 => (res == <byte>)
  <byte>;
end;


define abstract class <unsigned-integer-bit-frame> (<fixed-size-translated-leaf-frame>)
end;

define macro n-bit-unsigned-integer-definer
    { define n-bit-unsigned-integer(?:name; ?n:*) end }
     => { define class ?name (<unsigned-integer-bit-frame>)
            slot data :: limited(<integer>, min: 0, max: 2 ^ ?n - 1),
              required-init-keyword: data:;
          end;
          
          define inline method high-level-type (low-level-type == ?name)
            => (res :: <type>)
            limited(<integer>, min: 0, max: 2 ^ ?n - 1);
          end;

          define inline method field-size (type == ?name)
           => (length :: <integer>)
           ?n
          end; }
end;

define n-bit-unsigned-integer(<1bit-unsigned-integer>; 1) end;
define n-bit-unsigned-integer(<2bit-unsigned-integer>; 2) end;
define n-bit-unsigned-integer(<3bit-unsigned-integer>; 3) end;
define n-bit-unsigned-integer(<4bit-unsigned-integer>; 4) end;
define n-bit-unsigned-integer(<5bit-unsigned-integer>; 5) end;
define n-bit-unsigned-integer(<6bit-unsigned-integer>; 6) end;
define n-bit-unsigned-integer(<13bit-unsigned-integer>; 13) end;

define method parse-frame (frame-type :: subclass(<unsigned-integer-bit-frame>),
                           packet :: <byte-sequence>,
                           #key start :: <integer> = 0)
  => (value :: <integer>, next-unparsed :: <integer>)
  let result-size = frame-size(frame-type);
  if (packet.size * 8 < start + result-size)
    signal(make(<malformed-packet-error>))
  else
    let result = 0;
    for (i from start below start + result-size)
      //assumption: msb first
      result := logand(1, ash(packet[byte-offset(i)],
                              - (7 - bit-offset(i))))
                + ash(result, 1);
    end;
    values(result, result-size + start);
  end;
end;

define method assemble-frame (frame :: <unsigned-integer-bit-frame>)
  => (packet :: <bit-vector>)
  assemble-frame-as(frame.object-class, frame.data)
end;

define method assemble-frame-as(frame-type :: subclass(<unsigned-integer-bit-frame>),
                                 data :: <integer>)
 => (packet :: <bit-vector>)
  let result-size = frame-size(frame-type);
  let result = make(<bit-vector>, size: result-size);
  for (i from 0 below result-size)
    result[i] := logand(1, ash(data, i - result-size + 1));
  end;
  result;
end;

define method assemble-frame-into-as (frame-type :: subclass(<unsigned-integer-bit-frame>),
                                      data :: <integer>,
                                      packet :: <byte-vector>,
                                      start :: <integer>)
 => ()
  let result-size = frame-size(frame-type);
  for (i from start below start + result-size)
    packet[byte-offset(i)] := logior(packet[byte-offset(i)],
                                     ash(logand(1, ash(data, i - start - result-size + 1)),
                                         7 - bit-offset(i)));
  end;
end;

define method as (class == <string>, frame :: <unsigned-integer-bit-frame>)
  => (string :: <string>)
  concatenate("0x",
              integer-to-string(frame.data,
                                base: 16,
                                size: byte-offset(frame-size(frame) + 7) * 2));
end;

define abstract class <fixed-size-byte-vector-frame> (<fixed-size-untranslated-leaf-frame>)
  slot data :: <byte-vector>, required-init-keyword: data:;
end;

define macro n-byte-vector-definer
    { define n-byte-vector(?:name, ?n:*) end }
     => { define class ?name (<fixed-size-byte-vector-frame>)
          end;

          define inline method field-size (type == ?name) => (length :: <integer>)
            ?n * 8;
          end; }
end;

define sealed domain parse-frame (subclass(<fixed-size-byte-vector-frame>),
                                  <byte-sequence>);

define method parse-frame (frame-type :: subclass(<fixed-size-byte-vector-frame>),
                           packet :: <byte-sequence>,
                           #key start :: <integer> = 0)
  => (frame :: <fixed-size-byte-vector-frame>, next-unparsed :: <integer>)
  byte-aligned(start);
  let end-of-frame = start + field-size(frame-type);
  if (packet.size < byte-offset(end-of-frame))
    signal(make(<malformed-packet-error>))
  else
    values(make(frame-type,
                data: copy-sequence(packet,
                                    start: byte-offset(start),
                                    end: byte-offset(end-of-frame))),
           end-of-frame)
  end;
end;

define method assemble-frame (frame :: <fixed-size-byte-vector-frame>) => (packet :: <byte-vector>)
  frame.data;
end;

define method assemble-frame-into (frame :: <fixed-size-byte-vector-frame>,
                                   packet :: <byte-vector>,
                                   start :: <integer>)
  byte-aligned(start);
  copy-bytes(frame.data, 0, packet, byte-offset(start), byte-offset(frame-size(frame)));
end;

define method as (class == <string>, frame :: <fixed-size-byte-vector-frame>) => (res :: <string>)
  let out-stream = make(<string-stream>, direction: #"output");
  block()
    hexdump(out-stream, frame.data);
    out-stream.stream-contents;
  cleanup
    close(out-stream)
  end
end;

define method \= (frame1 :: <fixed-size-byte-vector-frame>,
                  frame2 :: <fixed-size-byte-vector-frame>)
 => (result :: <boolean>)
  frame1.data = frame2.data
end method;

define abstract class <big-endian-unsigned-integer-byte-frame> (<fixed-size-translated-leaf-frame>)
end;

define abstract class <little-endian-unsigned-integer-byte-frame> (<fixed-size-translated-leaf-frame>)
end;

define macro n-byte-unsigned-integer-definer
    { define n-byte-unsigned-integer(?:name; ?n:*) end }
     => { define class ?name ## "-big-endian-unsigned-integer>"
                 (<big-endian-unsigned-integer-byte-frame>)
            slot data :: limited(<integer>, min: 0, max: 2 ^ (8 * ?n) - 1),
              required-init-keyword: data:;
          end;
          
          define inline method high-level-type
              (low-level-type == ?name ## "-big-endian-unsigned-integer>")
            => (res :: <type>)
            limited(<integer>, min: 0, max: 2 ^ (8 * ?n) - 1);
          end;

          define inline method field-size (field == ?name ## "-big-endian-unsigned-integer>")
           => (length :: <integer>)
           ?n * 8
          end;


          define class ?name ## "-little-endian-unsigned-integer>"
                 (<little-endian-unsigned-integer-byte-frame>)
            slot data :: limited(<integer>, min: 0, max: 2 ^ (8 * ?n) - 1),
              required-init-keyword: data:;
          end;
          
          define inline method high-level-type
              (low-level-type == ?name ## "-little-endian-unsigned-integer>")
            => (res :: <type>)
            limited(<integer>, min: 0, max: 2 ^ (8 * ?n) - 1);
          end;

          define inline method field-size (field == ?name ## "-little-endian-unsigned-integer>")
           => (length :: <integer>)
           ?n * 8
          end; }
end;

define n-byte-unsigned-integer(<2byte; 2) end;
define n-byte-unsigned-integer(<3byte; 3) end;
//define n-byte-unsigned-integer(<4byte; 4) end;

define sealed domain parse-frame (subclass(<big-endian-unsigned-integer-byte-frame>),
                                  <byte-sequence>);

define method parse-frame (frame-type :: subclass(<big-endian-unsigned-integer-byte-frame>),
                           packet :: <byte-sequence>,
                           #key start :: <integer> = 0)
 => (value :: <integer>, next-unparsed :: <integer>)
 byte-aligned(start);
 let result-size = byte-offset(frame-size(frame-type));
 let byte-start = byte-offset(start);
 if (packet.size < byte-start + result-size)
   signal(make(<malformed-packet-error>))
 else
   let result = 0;
   for (i from byte-start below byte-start + result-size)
     result := packet[i] + ash(result, 8)
   end;
   values(result, start + 8 * result-size);
 end;
end;

define method assemble-frame (frame :: <big-endian-unsigned-integer-byte-frame>)
 => (packet :: <byte-vector>)
  assemble-frame-as(frame.object-class, frame.data);
end;

define method assemble-frame-as (frame-type :: subclass(<big-endian-unsigned-integer-byte-frame>),
                                 data :: <integer>)
  => (packet :: <byte-vector>)
  let result = make(<byte-vector>, size: byte-offset(frame-size(frame-type)), fill: 0);
  assemble-frame-into-as(frame-type, data, result, 0);
end;

define method assemble-frame-into-as (frame-type :: subclass(<big-endian-unsigned-integer-byte-frame>),
                                      data :: <integer>,
                                      packet :: type-union(<byte-vector>, <byte-vector-subsequence>),
                                      start :: <integer>)
  byte-aligned(start);
  for (i from 0 below frame-size(frame-type) by 8)
    packet[byte-offset(start + i)] := logand(#xff, ash(data, - (frame-size(frame-type) - i - 8)));
  end;
end;

define method as (class == <string>, frame :: <big-endian-unsigned-integer-byte-frame>)
 => (string :: <string>)
 concatenate("0x", integer-to-string(frame.data,
                                     base: 16,
                                     size: ash(2 * frame-size(frame.object-class), -3)));
end;

define sealed domain parse-frame (subclass(<little-endian-unsigned-integer-byte-frame>),
                                  <byte-sequence>);

define method parse-frame (frame-type :: subclass(<little-endian-unsigned-integer-byte-frame>),
                           packet :: <byte-sequence>,
                           #key start :: <integer> = 0)
 => (value :: <integer>, next-unparsed :: <integer>)
 byte-aligned(start);
 let result-size = byte-offset(frame-size(frame-type));
 let byte-start = byte-offset(start);
 if (packet.size < byte-start + result-size)
   signal(make(<malformed-packet-error>))
 else
   let result = 0;
   for (i from byte-start + result-size - 1 to byte-start by -1)
     result := packet[i] + ash(result, 8)
   end;
   values(result, start + 8 * result-size);
 end;
end;

define method assemble-frame (frame :: <little-endian-unsigned-integer-byte-frame>)
 => (packet :: <byte-vector>)
  assemble-frame-as(frame.object-class, frame.data);
end;

define method assemble-frame-as (frame-type :: subclass(<little-endian-unsigned-integer-byte-frame>),
                                 data :: <integer>)
  => (packet :: <byte-vector>)
  let result = make(<byte-vector>, size: byte-offset(frame-size(frame-type)), fill: 0);
  assemble-frame-into-as(frame-type, data, result, 0);
end;

define method assemble-frame-into-as (frame-type :: subclass(<little-endian-unsigned-integer-byte-frame>),
                                      data :: <integer>,
                                      packet :: <byte-vector>,
                                      start :: <integer>)
  byte-aligned(start);
  for (i from 0 below frame-size(frame-type) by 8)
    packet[byte-offset(start + i)] := logand(#xff, ash(data, - i));
  end;
end;

define method as (class == <string>, frame :: <little-endian-unsigned-integer-byte-frame>)
 => (string :: <string>)
 concatenate("0x", integer-to-string(frame.data,
                                     base: 16,
                                     size: ash(2 * frame-size(frame.object-class), -3)));
end;


define class <raw-frame> (<variable-size-untranslated-leaf-frame>)
  slot data :: <byte-vector>, required-init-keyword: data:;
end;

define method frame-size (raw-frame :: <raw-frame>) => (res :: <integer>)
  raw-frame.data.size * 8
end;

define method parse-frame (frame-type == <raw-frame>,
                           packet :: <byte-sequence>,
                           #key start :: <integer> = 0)
 => (frame :: <raw-frame>, next-unparsed :: <integer>)
 byte-aligned(start);
 if (packet.size < byte-offset(start))
   signal(make(<malformed-packet-error>))
 else
   values(make(<raw-frame>,
               data: copy-sequence(packet, start: byte-offset(start))),
          packet.size * 8)
 end
end;

define method assemble-frame (frame :: <raw-frame>)
 => (packet :: <byte-vector>)
 frame.data
end;

define method assemble-frame-into (frame :: <raw-frame>,
                                   packet :: <byte-vector>,
                                   start :: <integer>)
  byte-aligned(start);
  copy-bytes(frame.data, 0, packet, byte-offset(start), frame.data.size);
end;

define method as (class == <string>, frame :: <raw-frame>) => (res :: <string>)
  let out-stream = make(<string-stream>, direction: #"output");
  block()
    hexdump(out-stream, frame.data);
    out-stream.stream-contents;
  cleanup
    close(out-stream)
  end
end;

