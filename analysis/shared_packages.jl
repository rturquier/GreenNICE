using Mimi
using TidierData
using TidierFiles
using VegaLite
using Countries
using VegaDatasets

if !isdefined(Main, :GreenNICE)
    include("../src/GreenNICE.jl")
    using .GreenNICE
end
