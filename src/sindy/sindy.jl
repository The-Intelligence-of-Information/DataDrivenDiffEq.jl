function normalize_theta!(scales::AbstractArray, θ::AbstractArray)
    @assert length(scales) == size(θ, 1)
    @inbounds for (i, ti) in enumerate(eachrow(θ))
        scales[i] = norm(ti, 2)
        normalize!(ti, 2)
    end
    return
end

function rescale_xi!(Ξ::AbstractArray, scales::AbstractArray)
    @assert length(scales) == size(Ξ, 1)
    @inbounds for (si, ti) in zip(scales, eachrow(Ξ))
        ti .= ti / si
    end
    return
end

function rescale_theta!(θ::AbstractArray, scales::AbstractArray)
    @assert length(scales) == size(θ, 1)
    @inbounds for (i, ti) in enumerate(eachrow(θ))
        ti .= ti * scales[i]
    end
    return
end

"""
    sparse_regression(X, Y, basis, p, t, maxiter, opt, denoise, normalize, convergence_error)
    sparse_regression!(Xi, X, Y, basis, p, t, maxiter, opt, denoise, normalize, convergence_error)
    spares_regression!(Xi, Theta, Y, maxiter, opt, denoise, normalize, convergence_error)

Performs a sparse regression via the algorithm `opt <: AbstractOptimizer`. `maxiter` specifies the upper bound of the iterations
of the optimizer, `convergence_error` the breaking condition due to convergence.
`denoise` defines if the matrix holding candidate trajectories should be thresholded via the [optimal threshold for singular values](http://arxiv.org/abs/1305.5870).
`normalize` normalizes the matrix holding candidate trajectories via the L2-Norm over each function.

If the data matrices `X`, `Y` are given with a `Basis` `basis` and the additional information for parameters `p` and time points of the
measurements `t`, it returns the coefficient matrix `Xi` and the iterations taken.
This function is also available in place, which returns just the iterations.

If `Xi`, `Theta` and `Y` are given, the sparse regression will find the coefficients `Xi`, which minimize the objective and return the iterations needed.

# Example

```julia
opt = STRRidge()
maxiter = 10
c_error = 1e-3

Xi, iters = sparse_regression(X, Y, basis, [], [], maxiter, opt, false, false, c_error)

iters = sparse_regression!(Xi,X, Y, basis, [], [], maxiter, opt, false, false, c_error)

Xi2 = zeros(size(Y, 1), size(X, 1))
iters = sparse_regression!(Xi2, X, Y, maxiter, opt, false, false, c_error)
```
"""
function sparse_regression(X::AbstractArray, Ẋ::AbstractArray, Ψ::Basis, p::AbstractArray, t::AbstractVector , maxiter::Int64 , opt::T, denoise::Bool, normalize::Bool, convergence_error) where T <: Optimize.AbstractOptimizer
    @assert size(X)[end] == size(Ẋ)[end]
    nx, nm = size(X)
    ny, nm = size(Ẋ)

    Ξ = zeros(eltype(X), length(Ψ), ny)
    scales = ones(eltype(X), length(Ψ))
    θ = Ψ(X, p, t)

    denoise ? optimal_shrinkage!(θ') : nothing
    normalize ? normalize_theta!(scales, θ) : nothing

    Optimize.init!(Ξ, opt, θ', Ẋ')
    iters = Optimize.fit!(Ξ, θ', Ẋ', opt, maxiter = maxiter, convergence_error = convergence_error)

    normalize ? rescale_xi!(Ξ, scales) : nothing

    return Ξ, iters
end

function sparse_regression!(Ξ::AbstractArray, X::AbstractArray, Ẋ::AbstractArray, Ψ::Basis, p::AbstractArray , t::AbstractVector, maxiter::Int64 , opt::T, denoise::Bool, normalize::Bool, convergence_error) where T <: Optimize.AbstractOptimizer
    @assert size(X)[end] == size(Ẋ)[end]
    nx, nm = size(X)
    ny, nm = size(Ẋ)
    @assert size(Ξ) == (length(Ψ), ny)

    scales = ones(eltype(X), length(Ψ))
    θ = Ψ(X, p, t)

    denoise ? optimal_shrinkage!(θ') : nothing
    normalize ? normalize_theta!(scales, θ) : nothing

    Optimize.init!(Ξ, opt, θ', Ẋ')
    iters = Optimize.fit!(Ξ, θ', Ẋ', opt, maxiter = maxiter, convergence_error = convergence_error)

    normalize ? rescale_xi!(Ξ, scales) : nothing

    return iters
end

# For pareto
function sparse_regression!(Ξ::AbstractArray, θ::AbstractArray, Ẋ::AbstractArray, maxiter::Int64 , opt::T, denoise::Bool, normalize::Bool, convergence_error) where T <: Optimize.AbstractOptimizer

    scales = ones(eltype(Ξ), size(θ, 1))

    denoise ? optimal_shrinkage!(θ') : nothing
    normalize ? normalize_theta!(scales, θ) : nothing

    Optimize.init!(Ξ, opt, θ', Ẋ')'
    iters = Optimize.fit!(Ξ, θ', Ẋ', opt, maxiter = maxiter, convergence_error = convergence_error)

    normalize ? rescale_xi!(Ξ, scales) : nothing
    normalize ? rescale_theta!(θ, scales) : nothing

    return iters
end


# One Variable on multiple derivatives
function SInDy(X::AbstractArray{S, 1}, Ẋ::AbstractArray, Ψ::Basis; kwargs...) where S <: Number
    return SInDy(X', Ẋ, Ψ; kwargs...)
end

# Multiple on one
function SInDy(X::AbstractArray{S, 2}, Ẋ::AbstractArray{S, 1}, Ψ::Basis; kwargs...) where S <: Number
    return SInDy(X, Ẋ', Ψ; kwargs...)
end

# General
"""
    SInDy(X, Y, basis; p, t, opt, maxiter, convergence_error, denoise, normalize)
    SInDy(X, Y, basis, lambdas; weights, f_target, p, t, opt, maxiter, convergence_error, denoise, normalize)

Performs Sparse Identification of Nonlinear Dynamics given the data matrices `X` and `Y` via the `AbstractBasis` `basis.`
Keyworded arguments include the parameter (values) of the basis `p` and the timepoints `t` which are passed in optionally.
`opt` is an `AbstractOptimizer` useable for sparse regression, `maxiter` the maximum iterations to perform and `convergence_error` the
bound which causes the optimizer to stop.
`denoise` defines if the matrix holding candidate trajectories should be thresholded via the [optimal threshold for singular values](http://arxiv.org/abs/1305.5870).
`normalize` normalizes the matrix holding candidate trajectories via the L2-Norm over each function.


If `SInDy` is called with an additional array of thresholds contained in `lambdas`, it performs a multi objective optimization over all thresholds.
The best candidate is determined via the mapping onto a feature space `f` and an (scalar, positive definite) evaluation `g`.
The signature of should be `f(xi, theta, yi)` where `xi` are the coefficients of the sparse optimization,`theta` is the evaluated candidate library and `yi` are the rows of the matrix `Y`.
Returns a `SInDyResult`. If the pareto optimization is used, the result combines the best candidate for each row of `Y`.
"""
function SInDy(X::AbstractArray{S, 2}, Ẋ::AbstractArray{S, 2}, Ψ::Basis; p::AbstractArray = [], t::AbstractVector = [], maxiter::Int64 = 10, opt::T = Optimize.STRRidge(), denoise::Bool = false, normalize::Bool = true, convergence_error = eps()) where {T <: Optimize.AbstractOptimizer, S <: Number}
    Ξ, iters = sparse_regression(X, Ẋ, Ψ, p, t, maxiter, opt, denoise, normalize, convergence_error)
    convergence = iters < maxiter
    SparseIdentificationResult(Ξ, Ψ, iters, opt, convergence, Ẋ, X, p = p)
end



function SInDy(X::AbstractArray{S, 1}, Ẋ::AbstractArray, Ψ::Basis, thresholds::AbstractArray; kwargs...) where S <: Number
    return SInDy(X', Ẋ, Ψ, thresholds; kwargs...)
end

function SInDy(X::AbstractArray{S, 2}, Ẋ::AbstractArray{S, 1}, Ψ::Basis, thresholds::AbstractArray; kwargs...) where S <: Number
    return SInDy(X, Ẋ', Ψ, thresholds; kwargs...)
end

function SInDy(X, DX, Ψ::Basis, thresholds::AbstractArray ; f::Function = (xi, theta, dx)->[norm(xi, 0); norm(dx .- theta'*xi, 2)], g::Function = x->norm(x), p::AbstractArray = [], t::AbstractVector = [], maxiter::Int64 = 10, opt::T = STRRidge(),denoise::Bool = false, normalize::Bool = true, convergence_error = eps()) where {T <: Optimize.AbstractOptimizer}
    @assert size(X)[end] == size(DX)[end]
    nx, nm = size(X)
    ny, nm = size(DX)

    θ = Ψ(X, p, t)

    scales = ones(eltype(X), length(Ψ))

    ξ_tmp = zeros(eltype(X), length(Ψ), ny)
    Ξ_opt = zeros(eltype(X), length(Ψ), ny)

    iter_ = Inf
    _iter = Inf
    _thresh = Inf

    denoise ? optimal_shrinkage!(θ') : nothing
    normalize ? normalize_theta!(scales, θ) : nothing

    fg(xi, theta, dx) = (g∘f)(xi, theta, dx)
    
    @inbounds for j in 1:length(thresholds)
        set_threshold!(opt, thresholds[j])
        iter_ = sparse_regression!(view(ξ_tmp, :, :), view(θ, :, :), view(DX, :, :), maxiter, opt, false, false, convergence_error)
        normalize ? rescale_xi!(ξ_tmp, scales) : nothing
        @simd for i in 1:ny
            if j == 1
                Ξ_opt .= ξ_tmp
                _iter = iter_
                _thresh = thresholds[j]
            else
                if evaluate_pareto!(view(Ξ_opt, :, i), view(ξ_tmp, :, i), fg, view(θ, :, :), view(DX, i, :))
                    _iter = iter_
                    _thresh = thresholds[j]
                end
            end
        end
    end

    set_threshold!(opt, _thresh)
    #return Ξ_opt
    return SparseIdentificationResult(Ξ_opt, Ψ, _iter, opt, _iter < maxiter, DX, X, p = p)
end