include("/home/anton_hinneck/projects/github/GraphVisualization.jl/src/GraphVisualization.jl")
include("/home/anton_hinneck/projects/github/PowerGrids.jl/src/PowerGrids.jl")
using .PowerGrids, .GraphVisualization
using LightGraphs
using Ipopt, JuMP #, Mosek, MosekTools, ECOS
using Gurobi
dir = @__DIR__
cd(dir)

set_csv_path("/home/anton_hinneck/projects/github/pglib2csv/pglib/2020-08-21.19-54-30-275/csv")
PowerGrids.csv_cases(verbose = true)
PowerGrids.select_csv_case(4)
case = PowerGrids.loadCase() # 118 Bus ieee

include("plot_new.jl")

graph = PowerGrids.toGraph(case)

function get_x_start_offset(g, xvals, yvals)

    _edges = [LightGraphs.edges(g)...]
    _vertices = [LightGraphs.vertices(g)...]
    edges_start_at_bus = Vector{Vector{Int64}}()
    for i in 1:length(_vertices)
        push!(edges_start_at_bus, Vector{Int64}())
    end

    ctr = 1
    for e in _edges
        push!(edges_start_at_bus[e.src], ctr)
        ctr += 1
    end

    edge_start_offset = zeros(length(_edges))
    #println(edges_start_at_bus)

    for v in _vertices

        edges_lwr = Vector{Int64}()
        vals_lwr = Vector{Float64}()
        edges_gtr = Vector{Int64}()
        vals_gtr = Vector{Float64}()

        for e in edges_start_at_bus[v]

            if xvals[_edges[e].dst] < xvals[v]
                push!(edges_lwr, e)
                push!(vals_lwr, yvals[_edges[e].dst])
            else
                push!(edges_gtr, e)
                push!(vals_gtr, yvals[_edges[e].dst])
            end
        end

        perm_lwr = sortperm(vals_lwr)
        #permute!(vals_lwr, perm_lwr)
        permute!(edges_lwr, perm_lwr)

        perm_gtr = sortperm(vals_gtr, rev = true)
        #permute!(vals_gtr, perm_gtr)
        permute!(edges_gtr, perm_gtr)

        ctr = 1
        for e in edges_lwr
            edge_start_offset[e] = ctr
            ctr += 1
        end
        for e in edges_gtr
            edge_start_offset[e] = ctr
            ctr += 1
        end
    end

    return edge_start_offset
end

function compute_positions(g, W, H, padding; root = :upperleft, min_distx = 8, min_disty = 8, root_vertex = -1, x_os = 1, y_os_lwr = 1, y_os_gtr = 1)

    @assert padding <= W - padding "Error: Canvas empty (width)."
    @assert padding <= H - padding "Error: Canvas empty (height)."

    sp_adj, sp, seq = bfs(graph, initialization = 1)

    m = Model(Ipopt.Optimizer)
    #set_optimizer_attributes(m, "TimeLimit" => 60)
    set_optimizer_attributes(m, "mumps_mem_percent" => 64000)

    verts = [vertices(g)...]

    @variable(m, x[verts] >= 0)
    @variable(m, y[verts] >= 0)
    # @variable(m, right[v1 in verts, v2 in verts; v1 < v2], Bin)
    # @variable(m, lower[v1 in verts, v2 in verts; v1 < v2], Bin)
    @variable(m, dist >= 0)
    # @variable(m, dist_x >= 0)
    # @variable(m, dist_y >= 0)

    # Root vertex equals
    if root == :upperleft
        fix(x[6], padding + x_os, force = true)
        fix(y[6], padding + y_os_gtr, force = true)
    elseif root == :center
        fix(x[1], (W / 2), force = true)
        fix(y[1], (H / 2), force = true)
    elseif root == :leftcenter
        fix(x[1], padding + x_os, force = true)
        fix(y[1], (H / 2), force = true)
    end

    @constraint(m, Wlim_up[v in verts], x[v] - x_os >= padding)
    @constraint(m, Wlim_lw[v in verts], x[v] + x_os <= W - padding)

    @constraint(m, Hlim_up[v in verts], y[v] - y_os_gtr >= padding)
    @constraint(m, Hlim_lw[v in verts], y[v] + y_os_lwr <= H - padding)

    # @constraint(m, con_dist_x1[v1 in verts, v2 in verts; v1 < v2], dist_x + x_os <= x[v1] - x[v2] + W * (1 - right[v1,v2]))
    # @constraint(m, con_dist_x2[v1 in verts, v2 in verts; v1 < v2], dist_x + x_os <= x[v2] + x_os - x[v1] + W * right[v1,v2])
    # @constraint(m, con_dist_x3[v1 in verts, v2 in verts; v1 < v2], dist_y + y_os_gtr <= y[v1]- y[v2] + W * (1 - lower[v1,v2]))
    # @constraint(m, con_dist_x4[v1 in verts, v2 in verts; v1 < v2], dist_y + y_os_lwr <= y[v2] - y[v1] + W * lower[v1,v2])

    @constraint(m, distsq1[v1 in verts, v2 in verts], dist^2 <= 1 * (x[v1] - x[v2])^2 + (W/H) * (y[v1] - y[v2])^2)
    #@constraint(m, con_x[v1 in verts, v2 in sp_adj[v1], v3 in sp_adj[v1]; v1 < v2], x[v1] <= x[v2])

    #@objective(m, Max, (dist_x + dist_y))
    @objective(m, Max, dist)

    optimize!(m)
    objective_value(m)

    #println(string("Distance Value: ",value.(m[:dist_x])))

    return [value.(m[:x]).data, value.(m[:y]).data]
end

function plot(fig, graph, name, W, H; radius = 2, rect_w = 1, rect_h = 6, root = :center, lw = 1.0, v_line_dist = 2.0, lstyle = :rectangular, bstyle = :rectangle, font_size = 8, text_pad = 1.0, text_loc = :top)

    init_figure(fig, name, W, H)

    vertices = [LightGraphs.vertices(graph)...]
    edges = [LightGraphs.edges(graph)...]

    text_w_offset = 0
    text_h_offset = 0
    if text_loc == :top
        set_font_size(fig.cairo_context, font_size)
        max_height = 0
        max_width = 0
        for i in [LightGraphs.vertices(graph)...]
            text_dims = text_extents(fig.cairo_context, string(i))
            if text_dims[3] > max_width
                max_width = text_dims[3]
            end
            if text_dims[4] > max_height
                max_height = text_dims[4]
            end
        end
        text_w_offset = max_width
        text_h_offset = max_height
    end

    coords = compute_positions(graph, W, H, fig.padding, root = root, x_os = rect_w + text_w_offset / 2, y_os_lwr = rect_h, y_os_gtr = rect_h + text_h_offset)
    x_start_offset = get_x_start_offset(graph, coords[1], coords[2])
    xso = 2

    #println(x_start_offset)
    # coords contains x and y positions

    # PLOT EDGES
    ectr = 1
    if lstyle == :direct
        # Plot edges: direct
        for e in edges
            s = e.src
            d = e.dst
            set_line_width(fig.cairo_context, lw)
            set_source_rgb(fig.cairo_context, [0, 0, 1]...)
            move_to(fig.cairo_context, coords[1][s], coords[2][s])
            line_to(fig.cairo_context, coords[1][d], coords[2][d])
            stroke(fig.cairo_context)
        end
    elseif lstyle == :rectangular
        # Plot edges: rectangular
        for e in edges
            s = e.src
            d = e.dst

            set_line_width(fig.cairo_context, lw)
            set_source_rgb(fig.cairo_context, [0, 0, 1]...)

            # if x_start_offset[ectr] == 1.0 || x_start_offset[ectr] == 0.0

            #     move_to(fig.cairo_context, coords[1][s], coords[2][s])
            #     line_to(fig.cairo_context, coords[1][s], coords[2][d])
            #     line_to(fig.cairo_context, coords[1][d], coords[2][d])
            #     stroke(fig.cairo_context)

            #     if coords[1][s] < coords[1][d]
            #         arrow_head_to(fig.cairo_context, coords[1][d], coords[2][d], a_angle = 0, color = [0, 0, 1], ah_length = 8.0, ah_angle = pi/20, tip_mod = 2)
            #     else
            #         arrow_head_to(fig.cairo_context, coords[1][d], coords[2][d], a_angle = pi, color = [0, 0, 1], ah_length = 8.0, ah_angle = pi/20, tip_mod = 2)
            #     end

            # else

            offset = (x_start_offset[ectr])
            move_to(fig.cairo_context, coords[1][s], coords[2][s] + rect_h - v_line_dist * offset)
            line_to(fig.cairo_context, coords[1][s] + xso * offset + text_w_offset / 2, coords[2][s] + rect_h - v_line_dist * offset)
            line_to(fig.cairo_context, coords[1][s] + xso * offset + text_w_offset / 2, coords[2][d])
            line_to(fig.cairo_context, coords[1][d], coords[2][d])
            stroke(fig.cairo_context)

            if coords[1][s] < coords[1][d]
                arrow_head_to(fig.cairo_context, coords[1][d], coords[2][d], a_angle = 0, color = [0, 0, 1], ah_length = 8.0, ah_angle = pi/20, tip_mod = 2)
            else
                arrow_head_to(fig.cairo_context, coords[1][d], coords[2][d], a_angle = pi, color = [0, 0, 1], ah_length = 8.0, ah_angle = pi/20, tip_mod = 2)
            end
            #end
            ectr += 1
        end
    end

    # Plot vertices
    for v in vertices
        if bstyle == :circle
            set_source_rgb(fig.cairo_context, [0,0,0]...)
            circle(fig.cairo_context, coords[1][v], coords[2][v], radius)
            fill(fig.cairo_context)
        elseif bstyle == :rectangle
            set_source_rgb(fig.cairo_context, [0,0,0]...)
            set_source_rgb(fig.cairo_context, 0.0, 0.0, 0.0);
            set_line_width(fig.cairo_context, 1);
            rectangle(fig.cairo_context, coords[1][v] - rect_w, coords[2][v] - rect_h, 2 * rect_w, 2 * rect_h);
            #rectangle(cr, 180, 20, 80, 80);
            stroke_preserve(fig.cairo_context);
            fill(fig.cairo_context);

            if text_loc == :top
                set_font_size(fig.cairo_context, 8)
                vertex_id = string(v)
                text_dims = text_extents(fig.cairo_context, vertex_id)
                move_to(fig.cairo_context, coords[1][v] - text_dims[3] / 2, coords[2][v] - rect_h - text_pad)
                show_text(fig.cairo_context, vertex_id)
            end
        end
    end

    finish(fig.cairo_surface)

    return fig, coords
end

fig = figure()
plot(fig, graph, "cairoplot", 1200, 1200, root = :upperleft, lstyle = :rectangular)

# function plot_arrow(fig, graph, name, W, H; radius = 2, root = :center, lw = 1.0, lstyle = :rectangular)
#
#     init_figure(fig, name, W, H)
#
#     # move to center of canvas
#     circle(fig.cairo_context, 40, 20, 1)
#     fill(fig.cairo_context)
#     #circle(fig.cairo_context, 40 + 4.619, 20 - 1.913, 1)
#     #fill(fig.cairo_context)
#     # rel_line_to(fig.cairo_context, arrow_length * cos(arrow_angle), arrow_length * sin(arrow_angle))
#     # rel_move_to(fig.cairo_context, -arrowhead_length * cos(arrow_angle - arrowhead_angle), -arrowhead_length * sin(arrow_angle - arrowhead_angle))
#     arrow_head_to(fig.cairo_context, 40, 20, a_angle = 0, ah_angle = pi/8)
#     arrow_head_to(fig.cairo_context, 40, 20, a_angle = pi / 2, ah_angle = pi/8)
#     arrow_head_to(fig.cairo_context, 40, 20, a_angle = pi, ah_angle = pi/8)
#     arrow_head_to(fig.cairo_context, 40, 20, a_angle = 3 * pi/2, ah_angle = pi/8)
#
#     # arrow_head_to(fig.cairo_context, 40, 20, a_angle = 0, ah_angle = pi/8, offset = :zero, color = [1,0,0])
#     # arrow_head_to(fig.cairo_context, 40, 20, a_angle = pi/4, ah_angle = pi/8, offset = :zero, color = [1,0,0])
#     # arrow_head_to(fig.cairo_context, 40, 20, a_angle = pi, ah_angle = pi/8, offset = :zero, color = [1,0,0])
#     # arrow_head_to(fig.cairo_context, 40, 20, a_angle = 3*pi/2, ah_angle = pi/8, offset = :zero, color = [1,0,0])
#     # rel_line_to(fig.cairo_context, arrowhead_length * cos(arrow_angle - arrowhead_angle), arrowhead_length * sin(arrow_angle - arrowhead_angle))
#     # rel_line_to(fig.cairo_context, -arrowhead_length * cos(arrow_angle + arrowhead_angle), -arrowhead_length * sin(arrow_angle + arrowhead_angle))
#     #
#     # set_source_rgb(fig.cairo_context, 0,0,0)
#     # set_line_width(fig.cairo_context, lw)
#     # stroke(fig.cairo_context)
#
#     finish(fig.cairo_surface)
# end
#
# fig = figure()
# plot_arrow(fig, graph, "cairoplot", 200, 200, root = :upperleft, lstyle = :rectangular)
