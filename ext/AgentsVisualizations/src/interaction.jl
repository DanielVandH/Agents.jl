function Agents.add_interaction!(ax, p)
    if p.add_controls[]
        @assert !isnothing(ax) "Need `ax` to add model controls."
        stepclick, resetclick = add_controls!(ax.parent, p.abmobs[], p.spu)
        if !isempty(p.params[])
            @assert !isnothing(ax) "Need `ax` to add plots and parameter sliders."
            add_param_sliders!(ax.parent, p.abmobs[].model, p.params[], resetclick)
        end
    else
        stepclick = resetclick = nothing
    end

    return stepclick, resetclick
end

Agents.add_interaction!(ax) = add_interaction!(ax, first_abmplot_in(ax))

"Initialize standard model control buttons."
function add_controls!(fig, abmobs, spu)

    model, agent_step!, model_step!, adata, mdata, adf, mdf, when =
    getfield.(Ref(abmobs), (:model, :agent_step!, :model_step!, :adata, :mdata, :adf, :mdf, :when))

    init_dataframes!(model[], adata, mdata, adf, mdf)
    collect_data!(abmobs, model[], when, adata, mdata, adf, mdf)

    # Create new layout for control buttons
    controllayout = fig[end+1,:][1,1] = GridLayout(tellheight = true)

    # Sliders
    if abmspace(model[]) isa Agents.ContinuousSpace
        _sleepr, _sleep0 = 0:0.01:1, 0
    else
        _sleepr, _sleep0 = 0:0.01:2, 1
    end
    sg = SliderGrid(controllayout[1,1], (label = "spu", range = spu[]),
        (label = "sleep", range = _sleepr, startvalue = _sleep0),
    )
    speed, slep = [s.value for s in sg.sliders]

    # Step button
    step = Button(fig, label = "step\nmodel")
    on(step.clicks) do c
        Agents.step!(abmobs, speed[])
        collect_data!(abmobs, model[], when[], adata, mdata, adf, mdf)
    end
    # Run button
    run = Button(fig, label = "run\nmodel")
    isrunning = Observable(false)
    on(run.clicks) do c; isrunning[] = !isrunning[]; end
    on(run.clicks) do c
        @async while isrunning[]
            step.clicks[] = step.clicks[] + 1
            slep[] == 0 ? yield() : sleep(slep[])
            isopen(fig.scene) || break # crucial, ensures computations stop if closed window.
        end
    end
    # Reset button
    if agent_step! == Agents.dummystep && model_step! == Agents.dummystep
        agent_step! = Agents.agent_step_field(model)
        model_step! = Agents.model_step_field(model)
    end
    reset = Button(fig, label = "reset\nmodel")
    model0 = deepcopy(model[]) # backup initial model state
    on(reset.clicks) do c
        adf_nrow, mdf_nrow = Agents.DataFrames.nrow(adf[]), Agents.DataFrames.nrow(mdf[])
        offsets_adf, offsets_mdf = abmobs.offset_time_adf[][2], abmobs.offset_time_mdf[][2]
        append!(offsets_adf, fill(abmobs.offset_time_adf[][1][], adf_nrow - length(offsets_adf)))
        append!(offsets_mdf, fill(abmobs.offset_time_mdf[][1][], mdf_nrow - length(offsets_mdf)))
        abmobs.offset_time_adf[][1][] += abmtime(model[])
        abmobs.offset_time_mdf[][1][] += abmtime(model[])
        model[] = deepcopy(model0)
    end
    # Clear button
    clear = Button(fig, label = "clear\ndata")
    on(clear.clicks) do c
        timetype = typeof(abmtime(model[]))
        abmobs.offset_time_adf[] = (Ref(abmobs.offset_time_adf[][1][]), timetype[])
        abmobs.offset_time_mdf[] = (Ref(abmobs.offset_time_mdf[][1][]), timetype[])
        init_dataframes!(model[], adata, mdata, adf, mdf)
        collect_data!(abmobs, model[], when, adata, mdata, adf, mdf)
    end
    # Layout buttons
    controllayout[2, :] = Makie.hbox!(step, run, reset, clear; tellwidth = false)

    return step.clicks, reset.clicks
end

"Initialize agent and model dataframes."
function init_dataframes!(model, adata, mdata, adf, mdf)
    if !isnothing(adata)
        adf.val = Agents.init_agent_dataframe(model, adata)
    end
    if !isnothing(mdata)
        mdf.val = Agents.init_model_dataframe(model, mdata)
    end
    return nothing
end

function collect_data!(abmobs, model, when, adata, mdata, adf, mdf)
    if Agents.should_we_collect(abmtime(model), model, when)
        if !isnothing(adata)
            Agents.collect_agent_data!(adf[], model, adata)
            adf[] = adf[] # trigger Observable
        end
        if !isnothing(mdata)
            Agents.collect_model_data!(mdf[], model, mdata)
            mdf[] = mdf[] # trigger Observable
        end
    end
    return nothing
end

"Initialize parameter control sliders."
function add_param_sliders!(fig, model, params, resetclick)
    datalayout = fig[end,:][1,2] = GridLayout(tellheight = true)

    slidervals = Dict{Symbol, Observable}()
    tuples_for_slidergrid = []
    for (i, (k, vals)) in enumerate(params)
        startvalue = has_key(abmproperties(model[]), k) ?
            get_value(abmproperties(model[]), k) : vals[1]
        label = string(k)
        push!(tuples_for_slidergrid, (;label, range = vals, startvalue))
    end
    sg = SliderGrid(datalayout[1,1], tuples_for_slidergrid...; tellheight = true)
    for (i, (l, vals)) in enumerate(params)
        slidervals[l] = sg.sliders[i].value
    end

    # Update button
    update = Button(datalayout[end+1, :], label = "update", tellwidth = false)
    on(update.clicks) do c
        for (k, v) in pairs(slidervals)
            if has_key(abmproperties(model[]), k)
                set_value!(abmproperties(model[]), k, v[])
            else
                throw(KeyError("$k"))
            end
        end
    end
    # Ensure resetted model has new parameters
    on(resetclick) do c
        update.clicks[] = update.clicks[] + 1
    end
    return nothing
end
