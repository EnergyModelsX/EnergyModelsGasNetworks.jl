using Documenter, DocumenterCitations, DocumenterInterLinks, DocumenterMermaid

using TimeStruct
using EnergyModelsBase
using EnergyModelsGasNetworks

DocMeta.setdocmeta!(
    EnergyModelsGasNetworks,
    :DocTestSetup,
    :(using EnergyModelsGasNetworks);
    recursive = true,
)

# Copy the NEWS.md file
# news = "docs/src/manual/NEWS.md"
# cp("NEWS.md", news; force = true)

links = InterLinks(
    "TimeStruct" => "https://sintefore.github.io/TimeStruct.jl/stable/",
    "EnergyModelsBase" => "https://energymodelsx.github.io/EnergyModelsBase.jl/stable/",
)

bib = CitationBibliography(joinpath(@__DIR__, "src", "references.bib"); style=:authoryear)

Documenter.makedocs(
    sitename = "EnergyModelsGasNetworks",
    repo  = "https://gitlab.sintef.no/shimmer/EnergyModelsGasNetworks",
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        edit_link = "main",
        assets = String[],
    ),
    modules = [EnergyModelsGasNetworks],
    pages = [
        "Home" => "index.md",
        "Manual" => [
            "Quick Start" => "manual/quick-start.md",
            "Examples" => "manual/simple-example.md",
            "Release notes" => "manual/NEWS.md",
        ],
        "Background" => [
            "Overview" => "background/overview.md",
            "Theoretical Background" => "background/method.md",
            ],
        "Library" => [
            "Public" => "library/public.md",
            "Internal" => Any[
                "Functions" => "library/internal/functions.md",
                "Elements" => "library/internal/elements.md",
            ]
        ],
        # "Auxiliary Functions" => [
        #     "Scratch" => "aux-fun/scratch.md"],
    ],
    plugins = [links, bib],
    # remotes = nothing
)

# deploydocs(;
#     repo = "github.com/EnergyModelsX/EnergyModelsGasNetworks.jl.git",
# )
