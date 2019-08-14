using Yao, Yao.YaoBlocks.ConstGate, BenchmarkTools
using LinearAlgebra, Pkg
BLAS.set_num_threads(1)

nqubits=4:26
benchmarks = Dict()

layer(nbit::Int, x::Symbol) = layer(nbit, Val(x))
layer(nbit::Int, ::Val{:first}) = chain(nbit, put(i=>chain(Rx(0), Rz(0))) for i = 1:nbit);
layer(nbit::Int, ::Val{:last}) = chain(nbit, put(i=>chain(Rz(0), Rx(0))) for i = 1:nbit)
layer(nbit::Int, ::Val{:mid}) = chain(nbit, put(i=>chain(Rz(0), Rx(0), Rz(0))) for i = 1:nbit);
entangler(pairs) = chain(control(ctrl, target=>X) for (ctrl, target) in pairs);
function build_circuit(n, nlayers, pairs)
    circuit = chain(n)
    push!(circuit, layer(n, :first))
    for i in 2:nlayers
        push!(circuit, entangler(pairs))
        push!(circuit, layer(n, :mid))
    end
    push!(circuit, entangler(pairs))
    push!(circuit, layer(n, :last))
    return circuit
end

@info "benchmarking X"
benchmarks["X"] = map(nqubits) do k
    t = @benchmark apply!(st, $(put(k, 2=>X))) setup=(st=rand_state($k))
    minimum(t).time
end

@info "benchmarking H"
benchmarks["H"] = map(nqubits) do k
    t = @benchmark apply!(st, $(put(k, 2=>H))) setup=(st=rand_state($k))
    minimum(t).time
end

@info "benchmarking T"
benchmarks["T"] = map(nqubits) do k
    t = @benchmark apply!(st, $(put(k, 2=>ConstGate.T))) setup=(st=rand_state($k))
    minimum(t).time
end

@info "benchmarking CNOT"
benchmarks["CNOT"] = map(nqubits) do k
    t = @benchmark apply!(st, $(control(k, 2, 3=>X))) setup=(st=rand_state($k))
    minimum(t).time
end

@info "benchmarking CRx"
benchmarks["CRx(0.5)"] = map(nqubits) do k
    t = @benchmark apply!(st, $(control(k, 2, 3=>Rx(0.5)))) setup=(st=rand_state($k))
    minimum(t).time
end

@info "benchmarking Toffoli"
benchmarks["Toffoli"] = map(nqubits) do k
    t = @benchmark apply!(st, $(control(k, (2, 3), 1=>X))) setup=(st=rand_state($k))
    minimum(t).time
end

const qcbm_nqubits = 4:20

@info "benchmarking QCBM"
benchmarks["QCBM"] = map(qcbm_nqubits) do k
    t = @benchmark apply!(st, $(build_circuit(k, 9, [(i, mod1(i+1, k)) for i in 1:k]))) setup=(st=zero_state($k))
    minimum(t).time
end

@info "benchmarking QCBM batch"
benchmarks["QCBM_batch"] = map(4:15) do k
    t = @benchmark apply!(st, $(build_circuit(k, 9, [(i, mod1(i+1, k)) for i in 1:k]))) setup=(st=zero_state($k, nbatch=1000))
    minimum(t).time
end

@static if "CuYao" in keys(Pkg.installed())

    using CuYao

    @info "benchmarking QCBM cuda"
    benchmarks["QCBM_cuda"] = map(qcbm_nqubits) do k
        t = @benchmark apply!(st, $(build_circuit(k, 9, [(i, mod1(i+1, k)) for i in 1:k]))) setup=(st=cu(zero_state($k)))
        minimum(t).time
    end

    @info "benchmarking QCBM batch cuda"
    benchmarks["QCBM_cuda_batch"] = map(4:15) do k
        t = @benchmark apply!(st, $(build_circuit(k, 9, [(i, mod1(i+1, k)) for i in 1:k]))) setup=(st=cu(zero_state($k, nbatch=1000)))
        minimum(t).time
    end

end

using DataFrames, CSV
df = DataFrame(
    nqubits=4:26,
    X=benchmarks["X"],
    H=benchmarks["H"],
    T=benchmarks["T"],
    CNOT=benchmarks["CNOT"],
    CRx=benchmarks["CRx(0.5)"],
    Toffoli=benchmarks["Toffoli"])

@static if "CuYao" in keys(Pkg.installed())

df_qcbm = DataFrame(
    nqubits=qcbm_nqubits,
    QCBM=benchmarks["QCBM"],
    QCBM_cuda=benchmarks["QCBM_cuda"],
)

df_batch_qcbm = DataFrame(
    nqubits=4:15,
    QCBM_batch=benchmarks["QCBM_batch"],
    QCBM_cuda_batch=benchmarks["QCBM_cuda_batch"]
)

end

CSV.write(ARGS[1], df)
CSV.write(ARGS[2], df_qcbm)
CSV.write(ARGS[3], df_batch_qcbm)
