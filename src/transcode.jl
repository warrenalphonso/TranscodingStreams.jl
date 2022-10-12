# Transcode
# =========

"""
    transcode(::Type{C}, data::Vector{UInt8})::Vector{UInt8} where C<:Codec

Transcode `data` by applying a codec `C()`.

Note that this method does allocation and deallocation of `C()` in every call,
which is handy but less efficient when transcoding a number of objects.
`transcode(codec, data)` is a recommended method in terms of performance.

Examples
--------

```julia
julia> using CodecZlib

julia> data = b"abracadabra";

julia> compressed = transcode(ZlibCompressor, data);

julia> decompressed = transcode(ZlibDecompressor, compressed);

julia> String(decompressed)
"abracadabra"

```
"""
function Base.transcode(::Type{C}, data::ByteData) where {C<:Codec}
    codec = C()
    initialize(codec)
    try
        return transcode(codec, data)
    finally
        finalize(codec)
    end
end

"""
    transcode(codec::Codec, data::Vector{UInt8})::Vector{UInt8}

Transcode `data` by applying `codec`.

Note that this method does not initialize or finalize `codec`. This is
efficient when you transcode a number of pieces of data, but you need to call
[`TranscodingStreams.initialize`](@ref) and
[`TranscodingStreams.finalize`](@ref) explicitly.

Examples
--------

```julia
julia> using CodecZlib

julia> data = b"abracadabra";

julia> codec = ZlibCompressor();

julia> TranscodingStreams.initialize(codec)

julia> compressed = transcode(codec, data);

julia> TranscodingStreams.finalize(codec)

julia> codec = ZlibDecompressor();

julia> TranscodingStreams.initialize(codec)

julia> decompressed = transcode(codec, compressed);

julia> TranscodingStreams.finalize(codec)

julia> String(decompressed)
"abracadabra"

```
"""
function Base.transcode(codec::Codec, data::ByteData)
    input = Buffer(data)
    output = Buffer(initial_output_size(codec, buffermem(input)))
    code = startproc(codec, :write)
    n = minoutsize(codec, buffermem(input))

    local Δin, Δout

    while true
        makemargin!(output, n)
        try
            Δin, Δout, code = process(codec, buffermem(input), marginmem(output))
        finally
            consumed!(input, Δin)
            supplied!(output, Δout)
        end
        @debug(
            "called process()",
            code = code,
            input_size = buffersize(input),
            output_size = marginsize(output),
            input_delta = Δin,
            output_delta = Δout,
        )
        if code === :end
            if buffersize(input) > 0
                startproc(codec, :write)
                n = minoutsize(codec, buffermem(input))
                continue
            end
            resize!(output.data, output.marginpos - 1)
            return output.data
        else
            n = max(Δout, minoutsize(codec, buffermem(input)))
        end
    end
end

# Return the initial output buffer size.
function initial_output_size(codec::Codec, input::Memory)
    return max(
        minoutsize(codec, input),
        expectedsize(codec, input),
        8,  # just in case where both minoutsize and expectedsize are foolish
    )
end
