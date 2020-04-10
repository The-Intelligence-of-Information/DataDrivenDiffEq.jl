struct DMDPINV <: AbstractDMDAlg end;
struct DMDSVD <: AbstractDMDAlg end;

function estimate_operator(alg::DMDPINV, X, Y; atol::Real = 0, rtol::Real = 0)
    return Y * pinv(X; atol = atol, rtol = rtol)
end