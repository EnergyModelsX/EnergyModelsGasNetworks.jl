using Documenter, DocumenterCitations, DocumenterInterLinks, DocumenterMermaid

using TimeStruct
using EnergyModelsBase
using EnergyModelsPooling

DocMeta.setdocmeta!(
    EnergyModelsPooling,
    :DocTestSetup,
    :(using EnergyModelsPooling);
    recursive = true,
)

# Copy the NEWS.md file
# news = "docs/src/manual/NEWS.md"
# cp("NEWS.md", news; force = true)

links = InterLinks(
    "TimeStruct" => "https://sintefore.github.io/TimeStruct.jl/stable/",
    "EnergyModelsBase" => "https://energymodelsx.github.io/EnergyModelsBase.jl/stable/",
)

bib = CitationBibliography(joinpath(@__DIR__, "src", "references.bib"))

Documenter.makedocs(
    sitename = "EnergyModelsPooling",
    # repo  ="https://gitlab.sintef.no/shimmer/EnergyModelsPooling",
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        edit_link = "main",
        assets = String[],
    ),
    modules = [EnergyModelsPooling],
    pages = [
        "Home" => "index.md",
        "Manual" => [
            "Quick Start" => "manual/quick-start.md",
            "Examples" => "manual/simple-example.md",
            "Release notes" => "manual/NEWS.md",
        ],
        "Background" => ["background/background.md"],
        "Library" => [
            "Public" => "library/public.md",
            "Internal" => Any[
                "Functions" => "library/internal/functions.md",
            ]
        ],
        # "Auxiliary Functions" => [
        #     "Scratch" => "aux-fun/scratch.md"],
    ],
    plugins = [links, bib],
    remotes = nothing
)

# deploydocs(;
#     repo = "github.com/EnergyModelsX/EnergyModelsPooling.jl.git",
# )
