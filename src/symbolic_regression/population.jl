using ModelingToolkit
using DataDrivenDiffEq
using LinearAlgebra
using StatsBase
using DiffEqBase

import DataDrivenDiffEq: is_unary


struct OperationPool{F}
    ops::AbstractArray{F}
    unary::BitArray
    weights::AbstractWeights
end

OperationPool(ops::AbstractArray{Function}) = OperationPool(ops, is_unary.(ops, Number), Weights(ones(length(ops))))
DataDrivenDiffEq.is_unary(op::OperationPool, ind) = op.unary[ind]

Base.length(op::OperationPool) = length(op.ops)
Base.size(op::OperationPool, args...) = size(op.ops, args...)

function random_operation(op::OperationPool)
    idx = sample(1:length(op), op.weights)
    return (op.ops[idx], op.unary[idx])
end


mutable struct Candidate{B, S}
    basis::B
    score::S
end

Candidate(b::Basis) = Candidate(b, fill(-Inf, length(b)))

(c::Candidate)(args...) = c.basis(args...)

DataDrivenDiffEq.variables(c::Candidate) = variables(c.basis)
DataDrivenDiffEq.parameters(c::Candidate) = parameters(c.basis)
DataDrivenDiffEq.independent_variable(c::Candidate) = independent_variable(c.basis)
score(c::Candidate, ind = :) = c.score[ind]


Base.length(c::Candidate) = length(c.basis)
Base.size(c::Candidate, args...) = size(c.basis, args...) 

_select_features(f, rng, n) = sample(f[rng], n, replace = false, ordered = true)
_select_features(c::Candidate, rng, n) = _select_features(c.basis, rng, n)

function _conditional_feature!(features, i, op, selection_rng, maxiter = 100)
    op_ = features[1]
    op_in_features = true
    iter = 0
    while op_in_features && (iter <= maxiter)
        f,unary = random_operation(op)
        states = unary ? _select_features(features, selection_rng, 1) : _select_features(features, selection_rng, 2)
        op_ = Operation(f, states)
        op_in_features = any(map(x->isequal(op_, x), features))
        iter += 1
    end
    features[i] = op_
    return
end

function add_features!(c::Candidate, op::OperationPool, n_features::Int64 = 1, selection_rng = :, insertion_rng = nothing; maxiter = 10)
    n_basis = length(c)
    features = Array{Operation}(undef, n_basis+n_features)
    features[1:n_basis] .= simplify.(c.basis.basis)
    features[n_basis+1:end] .= ModelingToolkit.Constant(0)
    for i in n_basis:(n_basis+n_features)
        @views _conditional_feature!(features, i, op, selection_rng, maxiter)
    end
    if !isnothing(insertion_rng) && length(insertion_rng) == n_features && insertion_rng[end] <= length(c)
        @views for i in insertion_rng
            c.basis.basis[i] = features[i]
        end
    else
        for f in features[n_basis+1:end]
            push!(c.basis.basis, f)
        end
    end
    DataDrivenDiffEq.update!(c.basis)
    return
end


@variables x[1:4]
ops = [sin, cos, tanh, +, *, /, exp]
op = OperationPool(ops)
b = Basis(x, x, simplify_eqs = false)
c = Candidate(b)
@time add_features!(c, op, 6, 1:4)
println(c.basis)
println(unique(c.basis))
@time DataDrivenDiffEq.update!(c.basis)
