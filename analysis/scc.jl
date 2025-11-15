using Mimi
using TidierData
using TidierFiles
using VegaLite, VegaDatasets

include("../src/GreenNICE.jl")
using .GreenNICE

include("../src/components/welfare.jl")


function set_up_marginal_model(
    η::Real, θ::Real, α::Real, γ::Real, pulse_year::Int, pulse_size::Real
)::MarginalModel

    m = GreenNICE.create()
    update_params!(m, Dict(:η => η, :θ => θ, :α => α))
    update_param!(m, :quantile_recycle, :γ, γ)

    years = dim_keys(m, :time)
    n_years = length(years)
    pulse_year_index = findfirst(t -> t == pulse_year, years)

    pulse_series = zeros(n_years)
    pulse_series[pulse_year_index] = pulse_size

    mm = create_marginal_model(m, pulse_size)
    update_param!(mm.modified, :emissions, :co2_pulse, pulse_series)

    return mm
end

function get_model_data(mm::MarginalModel, pulse_year::Int)::DataFrame
    base_df = getdataframe(mm.base, :welfare => (:qcpc_post_recycle, :E_flow_percapita))
    population_df = getdataframe(mm.base, :welfare => :l)
    damages_df = @chain begin
        getdataframe(
            mm,
            :welfare => :E_flow_percapita,
            :quantile_recycle => :qcpc_damages,
        )
        # The marginal model gives changes per ton of CO2:
        # `(modified_model_value - base_model_value) / pulse_size`.
        # So marginal *damages* are the additive inverse of the changes in environment.
        @mutate(marginal_damage_to_E = -E_flow_percapita)
        @select(-(E_flow_percapita))
    end

    clean_df = @eval @chain $base_df begin
        @left_join($population_df)
        @left_join($damages_df)
        @rename(
            year = time,
            c = qcpc_post_recycle,
            E = E_flow_percapita,
            marginal_damage_to_c = qcpc_damages,
        )
        @mutate(
            t = year - $pulse_year, # t = 0 at pulse year. Used later to discount.
            l = l / 10, # population in a decile is a tenth of the country's population
        )
        @relocate(year, t)
        @mutate(
            # convert from thousand dollars and thousand people to dollars and people
            marginal_damage_to_c = marginal_damage_to_c * 10^3,
            marginal_damage_to_E = marginal_damage_to_E * 10^3,
            c = c * 10^3,
            E = E * 10^3,
            l = l * 10^3,
        )
    end

    return clean_df
end


@doc raw"""
        marginal_welfare_of_consumption(c, E, l, η, θ, α)

    First derivative of welfare with respect to consumption.

    ```math
    \partial_{c_i} W  =
        l_i
        \cdot (1 - \alpha) c_i^{\theta - 1}
        \cdot v(c_i, E_i)^{1 - \eta - \theta}
    ```
"""
function marginal_welfare_of_consumption(c, E, l, η, θ, α)
    return l * (1 - α) * c^(θ - 1) * v(c, E, θ, α)^(1 - η - θ)
end


@doc raw"""
        marginal_welfare_of_environment(c, E, l, η, θ, α)

    First derivative of welfare with respect to environment.

    ```math
    \partial_{E_i} W  =
        l_i
        \cdot \alpha E_i^{\theta - 1}
        \cdot v(c_i, E_i)^{1 - \eta - \theta}
    ```
"""
function marginal_welfare_of_environment(c, E, l, η, θ, α)
    return l * α * E^(θ - 1) * v(c, E, θ, α)^(1 - η - θ)
end


function get_marginal_utility_at_present_average(df::DataFrame, η::Real, θ::Real, α::Real)
    present_average_df = @chain df begin
        @filter(t == 0)
        @summarize(
            c = mean(c),
            E = mean(E),
        )
    end
    present_average_c = present_average_df.c[1]
    present_average_E = present_average_df.E[1]
    marginal_utility_at_present_average = marginal_welfare_of_consumption(
        present_average_c, present_average_E, 1, η, θ, α
    )
    return marginal_utility_at_present_average
end


function prepare_df_for_SCC(df::DataFrame, η::Real, θ::Real, α::Real)::DataFrame
    prepared_df = @eval @chain $df begin
        @mutate(
            ∂_cW = marginal_welfare_of_consumption(c, E, l, $η, $θ, $α),
            ∂_cE = marginal_welfare_of_environment(c, E, l, $η, $θ, $α),
        )
        @group_by(year)
        @ungroup()
    end
    return prepared_df
end


@doc raw"""
        apply_SCC_decomposition_formula(
            prepared_df::DataFrame, reference_marginal_utility::Real, ρ::Real
        )::DataFrame

    Get present value of equity-weighted, money-metric damages to `c` and `E`.

    The social cost of carbon (SCC) is equal to the sum of the present cost of marginal
    damages to consumption `c`, and to environment `E`:
    ```math
      \sum_t \beta^t \sum_{i} \partial_{c_{i,t}}{W_t} \frac{dc_i}{de}
    + \sum_t \beta^t \sum_{i} \partial_{E_{i,t}}{W_t} \frac{dE_i}{de}.
    ```

    Marginal damages to consumption ``\frac{dc_i}{de}`` are called `marginal_damage_to_c` in
    the dataframe, and marginal damages to the environment, ``\frac{dE_i}{de}``, are coded
    as `marginal_damage_to_E`.
"""
function apply_SCC_decomposition_formula(
    prepared_df::DataFrame, reference_marginal_utility::Real, ρ::Real
)::DataFrame
    β = 1 / (1 + ρ)
    SCC_df = @eval @chain $prepared_df begin
        @group_by(year)
        # Exclude 4 small countries with E = 0 because the have infinite ∂_cE
        @filter(E > 0)
        @summarize(
            t = unique(t),
            welfare_loss_c = sum(∂_cW * marginal_damage_to_c),
            welfare_loss_E = sum(∂_cE * marginal_damage_to_E),
        )
        @filter(t >= 0)
        @summarize(
            present_cost_of_damages_to_c = 1 / $reference_marginal_utility
                                           * sum($β^t * welfare_loss_c),
            present_cost_of_damages_to_E = 1 / $reference_marginal_utility
                                           * sum($β^t * welfare_loss_E),
        )
    end
    return SCC_df
end

"""
        get_SCC_decomposition(
            η::Real, θ::Real, α::Real, γ::Real, ρ::Real;
            pulse_year::Int=2025, pulse_size::Real=1.
        )::DataFrame

    Get social cost of carbon as damages to consumption and damages to the environment.

    Run a version of GreenNICE with the parameters supplied to the function, as well as an
    identical model with an additional `pulse_size` tons of CO2 in year `pulse_year`.
    Compare consumption and environment between the two models, and compute the present
    value of damages analytically.

    Return a one-line `Dataframe` with two `Float64` columns:
    - `present_cost_of_damages_to_c`,
    - `present_cost_of_damages_to_E`.

    The sum of these two numbers is the social cost of carbon (SCC). See function
    `apply_SCC_decomposition_formula` for mathematical details.

    # Arguments
    - `η::Real`: inequality aversion (coefficient of relative risk aversion).
    - `θ::Real`: substitutability parameter. Accepts value between -∞ and 1.
    - `α::Real`: share of `environment` the utility function. Must be in ``[0, 1]``.
    - `γ::Real`: within-country inequality parameter. 0 means no within-country inequality.
        1 is the standard calibration.
    - `ρ::Real`: rate of pure time preference (utility discount rate).
    - `pulse_year::Int`: year where the CO2 marginal pulse is emmitted, and year of
        reference for the SCC.
    - `pulse_size::Real`: size of the CO2 pulse, in tons.
"""
function get_SCC_decomposition(
    η::Real, θ::Real, α::Real, γ::Real, ρ::Real; pulse_year::Int=2025, pulse_size::Real=1.
)::DataFrame
    mm = set_up_marginal_model(η, θ, α, γ, pulse_year, pulse_size)
    run(mm)
    model_df = get_model_data(mm, pulse_year)

    reference_marginal_utility = get_marginal_utility_at_present_average(model_df, η, θ, α)

    SCC_decomposition_df = @chain begin
        prepare_df_for_SCC(model_df, η, θ, α)
        apply_SCC_decomposition_formula(_, reference_marginal_utility, ρ)
    end

    return SCC_decomposition_df
end


"""
        get_SCC_decomposition(
        η::Real, θ::Real, α::Real, γ_list::Vector, ρ::Real; kwargs...
    )::DataFrame

    Get SCC decomposition for a vector of γ values.

    Apply `get_SCC_decomposition` for each value of γ provided in `γ_list`.
    Return a Dataframe with as many rows as values in `γ_list`, with three columns:
    - `γ`, equal to `γ_list`,
    - `present_cost_of_damages_to_c`,
    - `present_cost_of_damages_to_E`.
"""
function get_SCC_decomposition(
    η::Real, θ::Real, α::Real, γ_list::Vector, ρ::Real; kwargs...
)::DataFrame
    df_list = map(γ -> get_SCC_decomposition(η, θ, α, γ, ρ; kwargs...), γ_list)
    concatenated_df = reduce(vcat, df_list)
    SCC_decomposition_df = @eval @chain $concatenated_df begin
        @mutate(γ = $γ_list)
        @relocate(γ)
    end
    return SCC_decomposition_df
end


function plot_SCC_decomposition(SCC_decomposition_df::DataFrame)::VegaLite.VLSpec
    damages_to_E_with_equal_deciles = @chain SCC_decomposition_df begin
        @filter(γ == 0)
        @pull(present_cost_of_damages_to_E)
    end

    # Wrangle and reshape to fit VegaLite requirements
    plot_df = @eval @chain $SCC_decomposition_df begin
        @mutate(
            interaction = present_cost_of_damages_to_E
                            - $damages_to_E_with_equal_deciles,
            non_interaction = present_cost_of_damages_to_c
                                + $damages_to_E_with_equal_deciles,
        )
        @pivot_longer(
            (interaction, non_interaction),
            names_to="interaction",
            values_to="SCC_part"
        )
    end

    plot = plot_df |> @vlplot(:area, x="γ:q", y="SCC_part:q", color="interaction:N")
    return plot
end

function apply_SCC_decomposition_formula_country(
    prepared_df::DataFrame,
    reference_marginal_utility::Real,
    ρ::Real,
    )::DataFrame

        β = 1 / (1 + ρ)
        SCC_df = @eval @chain $prepared_df begin
            @group_by(year, country)
            # Exclude 4 small countries with E = 0 because the have infinite ∂_cE
            @filter(E > 0)
            @summarize(
                t = first(t),
                country = first(country),

                welfare_loss_c = sum(∂_cW * marginal_damage_to_c),
                welfare_loss_E = sum(∂_cE * marginal_damage_to_E),
            )
            @filter(t >= 0)
            @ungroup
            @group_by(country)
            @summarize(
                present_cost_of_damages_to_c = 1 / $reference_marginal_utility
                                            * sum($β^t * welfare_loss_c),
                present_cost_of_damages_to_E = 1 / $reference_marginal_utility
                                            * sum($β^t * welfare_loss_E),
            )
        end

    return SCC_df
end

function get_SCC_decomposition_country(
    η::Real, θ::Real, α::Real, γ::Real, ρ::Real; pulse_year::Int=2025, pulse_size::Real=1.
)::DataFrame
    mm = set_up_marginal_model(η, θ, α, γ, pulse_year, pulse_size)
    run(mm)
    model_df = get_model_data(mm, pulse_year)

    reference_marginal_utility = get_marginal_utility_at_present_average(model_df, η, θ, α)

    SCC_decomposition_df = @chain begin
        prepare_df_for_SCC(model_df, η, θ, α)
        apply_SCC_decomposition_formula_country(_, reference_marginal_utility, ρ)
    end

    return SCC_decomposition_df
end

function get_SCC_decomposition_country(
    η::Real, θ::Real, α::Real, γ_list::Vector, ρ::Real; kwargs...
)::DataFrame
    df_list = map(γ -> begin
        concatenated_df = get_SCC_decomposition_country(η, θ, α, γ, ρ; kwargs...)
        concatenated_df.γ = fill(γ, nrow(concatenated_df))
        concatenated_df
    end, γ_list)

    SCC_decomposition_df = reduce(vcat, df_list)

    return SCC_decomposition_df
end

function map_SCC_decomposition_country( SCC_decomposition_df::DataFrame)

    #Calculate interaction
    no_inequality_df = @chain SCC_decomposition_df begin
        @filter(γ == 0)
        @select(country, no_inequality_damage_E = present_cost_of_damages_to_E)
    end

    inequality_df = @chain SCC_decomposition_df begin
        @filter(γ == 1)
        @select(country, inequality_damage_E = present_cost_of_damages_to_E)
    end

    interaction_df = @chain innerjoin(inequality_df, no_inequality_df, on = :country) begin
        @mutate(interaction = inequality_damage_E - no_inequality_damage_E)
        @mutate(interaction_pct = (- interaction) / inequality_damage_E * 100)
    end

    interaction_df.id = [alpha3_to_numeric[string(iso3)] for iso3 in interaction_df.country]

    #plot
    world110m = dataset("world-110m")

    map_interaction = @vlplot(
        width = 640,
        height = 360,
        title = "Interaction effect of within country inequality (USD)",
        projection = {type = :equirectangular}
    ) +
    @vlplot(
        data = {
            values = world110m,
            format = {
                type = :topojson,
                feature = :countries
            }
        },
        transform = [{
            lookup = "id",
            from = {
                data = interaction_df,
                key = :id,
                fields = ["interaction"]
            }
        }],
        mark = :geoshape,
        encoding = {
            color = {
                field = "interaction",
                type = "quantitative",
                title = "Interaction cost",
                scale = {
                    scheme = "redblue"
                }
            }
        }
    )

    map_percentage_interaction = @vlplot(
        width = 640,
        height = 360,
        title = "Interaction effect of within country inequality (USD)",
        projection = {type = :equirectangular}
    ) +
    @vlplot(
        data = {
            values = world110m,
            format = {
                type = :topojson,
                feature = :countries
            }
        },
        transform = [{
            lookup = "id",
            from = {
                data = interaction_df,
                key = :id,
                fields = ["interaction_pct"]
            }
        }],
        mark = :geoshape,
        encoding = {
            color = {
                field = "interaction_pct",
                type = "quantitative",
                title = "Interaction percentage change",
                scale = {
                    scheme = "redblue"
                }
            }
        }
    )

end


alpha3_to_numeric = Dict(
    "AFG" => 4,    # Afghanistan
    "ALB" => 8,    # Albania
    "DZA" => 12,   # Algeria
    "ASM" => 16,   # American Samoa
    "AND" => 20,   # Andorra
    "AGO" => 24,   # Angola
    "AIA" => 660,  # Anguilla
    "ATA" => 10,   # Antarctica
    "ATG" => 28,   # Antigua and Barbuda
    "ARG" => 32,   # Argentina
    "ARM" => 51,   # Armenia
    "ABW" => 533,  # Aruba
    "AUS" => 36,   # Australia
    "AUT" => 40,   # Austria
    "AZE" => 31,   # Azerbaijan
    "BHS" => 44,   # Bahamas (the)
    "BHR" => 48,   # Bahrain
    "BGD" => 50,   # Bangladesh
    "BRB" => 52,   # Barbados
    "BLR" => 112,  # Belarus
    "BEL" => 56,   # Belgium
    "BLZ" => 84,   # Belize
    "BEN" => 204,  # Benin
    "BMU" => 60,   # Bermuda
    "BTN" => 64,   # Bhutan
    "BOL" => 68,   # Bolivia (Plurinational State of)
    "BES" => 535,  # Bonaire, Sint Eustatius and Saba
    "BIH" => 70,   # Bosnia and Herzegovina
    "BWA" => 72,   # Botswana
    "BVT" => 74,   # Bouvet Island
    "BRA" => 76,   # Brazil
    "IOT" => 86,   # British Indian Ocean Territory (the)
    "BRN" => 96,   # Brunei Darussalam
    "BGR" => 100,  # Bulgaria
    "BFA" => 854,  # Burkina Faso
    "BDI" => 108,  # Burundi
    "CPV" => 132,  # Cabo Verde
    "KHM" => 116,  # Cambodia
    "CMR" => 120,  # Cameroon
    "CAN" => 124,  # Canada
    "CYM" => 136,  # Cayman Islands (the)
    "CAF" => 140,  # Central African Republic (the)
    "TCD" => 148,  # Chad
    "CHL" => 152,  # Chile
    "CHN" => 156,  # China
    "CXR" => 162,  # Christmas Island
    "CCK" => 166,  # Cocos (Keeling) Islands (the)
    "COL" => 170,  # Colombia
    "COM" => 174,  # Comoros (the)
    "COD" => 180,  # Congo (the Democratic Republic of the)
    "COG" => 178,  # Congo (the)
    "COK" => 184,  # Cook Islands (the)
    "CRI" => 188,  # Costa Rica
    "HRV" => 191,  # Croatia
    "CUB" => 192,  # Cuba
    "CUW" => 531,  # Curaçao
    "CYP" => 196,  # Cyprus
    "CZE" => 203,  # Czechia
    "CIV" => 384,  # Côte d'Ivoire
    "DNK" => 208,  # Denmark
    "DJI" => 262,  # Djibouti
    "DMA" => 212,  # Dominica
    "DOM" => 214,  # Dominican Republic (the)
    "ECU" => 218,  # Ecuador
    "EGY" => 818,  # Egypt
    "SLV" => 222,  # El Salvador
    "GNQ" => 226,  # Equatorial Guinea
    "ERI" => 232,  # Eritrea
    "EST" => 233,  # Estonia
    "SWZ" => 748,  # Eswatini
    "ETH" => 231,  # Ethiopia
    "FLK" => 238,  # Falkland Islands (the) [Malvinas]
    "FRO" => 234,  # Faroe Islands (the)
    "FJI" => 242,  # Fiji
    "FIN" => 246,  # Finland
    "FRA" => 250,  # France
    "GUF" => 254,  # French Guiana
    "PYF" => 258,  # French Polynesia
    "ATF" => 260,  # French Southern Territories (the)
    "GAB" => 266,  # Gabon
    "GMB" => 270,  # Gambia (the)
    "GEO" => 268,  # Georgia
    "DEU" => 276,  # Germany
    "GHA" => 288,  # Ghana
    "GIB" => 292,  # Gibraltar
    "GRC" => 300,  # Greece
    "GRL" => 304,  # Greenland
    "GRD" => 308,  # Grenada
    "GLP" => 312,  # Guadeloupe
    "GUM" => 316,  # Guam
    "GTM" => 320,  # Guatemala
    "GGY" => 831,  # Guernsey
    "GIN" => 324,  # Guinea
    "GNB" => 624,  # Guinea-Bissau
    "GUY" => 328,  # Guyana
    "HTI" => 332,  # Haiti
    "HMD" => 334,  # Heard Island and McDonald Islands
    "VAT" => 336,  # Holy See (the)
    "HND" => 340,  # Honduras
    "HKG" => 344,  # Hong Kong
    "HUN" => 348,  # Hungary
    "ISL" => 352,  # Iceland
    "IND" => 356,  # India
    "IDN" => 360,  # Indonesia
    "IRN" => 364,  # Iran (Islamic Republic of)
    "IRQ" => 368,  # Iraq
    "IRL" => 372,  # Ireland
    "IMN" => 833,  # Isle of Man
    "ISR" => 376,  # Israel
    "ITA" => 380,  # Italy
    "JAM" => 388,  # Jamaica
    "JPN" => 392,  # Japan
    "JEY" => 832,  # Jersey
    "JOR" => 400,  # Jordan
    "KAZ" => 398,  # Kazakhstan
    "KEN" => 404,  # Kenya
    "KIR" => 296,  # Kiribati
    "PRK" => 408,  # Korea (the Democratic People's Republic of)
    "KOR" => 410,  # Korea (the Republic of)
    "KWT" => 414,  # Kuwait
    "KGZ" => 417,  # Kyrgyzstan
    "LAO" => 418,  # Lao People's Democratic Republic (the)
    "LVA" => 428,  # Latvia
    "LBN" => 422,  # Lebanon
    "LSO" => 426,  # Lesotho
    "LBR" => 430,  # Liberia
    "LBY" => 434,  # Libya
    "LIE" => 438,  # Liechtenstein
    "LTU" => 440,  # Lithuania
    "LUX" => 442,  # Luxembourg
    "MAC" => 446,  # Macao
    "MDG" => 450,  # Madagascar
    "MWI" => 454,  # Malawi
    "MYS" => 458,  # Malaysia
    "MDV" => 462,  # Maldives
    "MLI" => 466,  # Mali
    "MLT" => 470,  # Malta
    "MHL" => 584,  # Marshall Islands (the)
    "MTQ" => 474,  # Martinique
    "MRT" => 478,  # Mauritania
    "MUS" => 480,  # Mauritius
    "MYT" => 175,  # Mayotte
    "MEX" => 484,  # Mexico
    "FSM" => 583,  # Micronesia (Federated States of)
    "MDA" => 498,  # Moldova (the Republic of)
    "MCO" => 492,  # Monaco
    "MNG" => 496,  # Mongolia
    "MNE" => 499,  # Montenegro
    "MSR" => 500,  # Montserrat
    "MAR" => 504,  # Morocco
    "MOZ" => 508,  # Mozambique
    "MMR" => 104,  # Myanmar
    "NAM" => 516,  # Namibia
    "NRU" => 520,  # Nauru
    "NPL" => 524,  # Nepal
    "NLD" => 528,  # Netherlands (the)
    "NCL" => 540,  # New Caledonia
    "NZL" => 554,  # New Zealand
    "NIC" => 558,  # Nicaragua
    "NER" => 562,  # Niger (the)
    "NGA" => 566,  # Nigeria
    "NIU" => 570,  # Niue
    "NFK" => 574,  # Norfolk Island
    "MNP" => 580,  # Northern Mariana Islands (the)
    "NOR" => 578,  # Norway
    "OMN" => 512,  # Oman
    "PAK" => 586,  # Pakistan
    "PLW" => 585,  # Palau
    "PSE" => 275,  # Palestine, State of
    "PAN" => 591,  # Panama
    "PNG" => 598,  # Papua New Guinea
    "PRY" => 600,  # Paraguay
    "PER" => 604,  # Peru
    "PHL" => 608,  # Philippines (the)
    "PCN" => 612,  # Pitcairn
    "POL" => 616,  # Poland
    "PRT" => 620,  # Portugal
    "PRI" => 630,  # Puerto Rico
    "QAT" => 634,  # Qatar
    "MKD" => 807,  # Republic of North Macedonia
    "ROU" => 642,  # Romania
    "RUS" => 643,  # Russian Federation (the)
    "RWA" => 646,  # Rwanda
    "REU" => 638,  # Réunion
    "BLM" => 652,  # Saint Barthélemy
    "SHN" => 654,  # Saint Helena, Ascension and Tristan da Cunha
    "KNA" => 659,  # Saint Kitts and Nevis
    "LCA" => 662,  # Saint Lucia
    "MAF" => 663,  # Saint Martin (French part)
    "SPM" => 666,  # Saint Pierre and Miquelon
    "VCT" => 670,  # Saint Vincent and the Grenadines
    "WSM" => 882,  # Samoa
    "SMR" => 674,  # San Marino
    "STP" => 678,  # Sao Tome and Principe
    "SAU" => 682,  # Saudi Arabia
    "SEN" => 686,  # Senegal
    "SRB" => 688,  # Serbia
    "SYC" => 690,  # Seychelles
    "SLE" => 694,  # Sierra Leone
    "SGP" => 702,  # Singapore
    "SXM" => 534,  # Sint Maarten (Dutch part)
    "SVK" => 703,  # Slovakia
    "SVN" => 705,  # Slovenia
    "SLB" => 90,   # Solomon Islands
    "SOM" => 706,  # Somalia
    "ZAF" => 710,  # South Africa
    "SGS" => 239,  # South Georgia and the South Sandwich Islands
    "SSD" => 728,  # South Sudan
    "ESP" => 724,  # Spain
    "LKA" => 144,  # Sri Lanka
    "SDN" => 729,  # Sudan (the)
    "SUR" => 740,  # Suriname
    "SJM" => 744,  # Svalbard and Jan Mayen
    "SWE" => 752,  # Sweden
    "CHE" => 756,  # Switzerland
    "SYR" => 760,  # Syrian Arab Republic
    "TWN" => 158,  # Taiwan (Province of China)
    "TJK" => 762,  # Tajikistan
    "TZA" => 834,  # Tanzania, United Republic of
    "THA" => 764,  # Thailand
    "TLS" => 626,  # Timor-Leste
    "TGO" => 768,  # Togo
    "TKL" => 772,  # Tokelau
    "TON" => 776,  # Tonga
    "TTO" => 780,  # Trinidad and Tobago
    "TUN" => 788,  # Tunisia
    "TUR" => 792,  # Turkey
    "TKM" => 795,  # Turkmenistan
    "TCA" => 796,  # Turks and Caicos Islands (the)
    "TUV" => 798,  # Tuvalu
    "UGA" => 800,  # Uganda
    "UKR" => 804,  # Ukraine
    "ARE" => 784,  # United Arab Emirates (the)
    "GBR" => 826,  # United Kingdom of Great Britain and Northern Ireland (the)
    "UMI" => 581,  # United States Minor Outlying Islands (the)
    "USA" => 840,  # United States of America (the)
    "URY" => 858,  # Uruguay
    "UZB" => 860,  # Uzbekistan
    "VUT" => 548,  # Vanuatu
    "VEN" => 862,  # Venezuela (Bolivarian Republic of)
    "VNM" => 704,  # Viet Nam
    "VGB" => 92,   # Virgin Islands (British)
    "VIR" => 850,  # Virgin Islands (U.S.)
    "WLF" => 876,  # Wallis and Futuna
    "ESH" => 732,  # Western Sahara
    "YEM" => 887,  # Yemen
    "ZMB" => 894,  # Zambia
    "ZWE" => 716,  # Zimbabwe
    "ALA" => 248   # Åland Islands
)
