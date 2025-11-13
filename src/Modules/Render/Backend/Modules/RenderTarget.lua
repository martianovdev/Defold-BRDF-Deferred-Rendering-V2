-- render_target.lua
local RenderTarget = {}

function RenderTarget:new(width, height, attachments)
    local this = {
        render_target = nil,
        width = width,
        height = height,
        clear_buffers = {},
        attachments = attachments or {},
        buffers = {},
        constants = render.constant_buffer(),

        init = function(this)
            for _, attachment in ipairs(this.attachments) do
                local buffer_type = attachment.buffer_type
                local format = attachment.format

                this.buffers[buffer_type] = {
                    format = format,
                    width = attachment.width or this.width,
                    height = attachment.height or this.height,
                    min_filter = attachment.min_filter or render.FILTER_LINEAR,
                    mag_filter = attachment.mag_filter or render.FILTER_LINEAR,
                    u_wrap = attachment.u_wrap or render.WRAP_CLAMP_TO_EDGE,
                    v_wrap = attachment.v_wrap or render.WRAP_CLAMP_TO_EDGE
                }

                -- Default clear values
                if buffer_type == graphics.BUFFER_TYPE_DEPTH_BIT then
                    this.clear_buffers[buffer_type] = 1
                    this.buffers[buffer_type].flags = render.TEXTURE_BIT
                elseif buffer_type == graphics.BUFFER_TYPE_STENCIL_BIT then
                    this.clear_buffers[buffer_type] = 0
                    this.buffers[buffer_type].flags = render.TEXTURE_BIT
                else
                    if(buffer_type == graphics.BUFFER_TYPE_COLOR0_BIT) then
                        this.clear_buffers[buffer_type] = attachment.clear_color or vmath.vector4(0, 0, 0, 0)
                    end

                end

                this.clear_buffers[render.BUFFER_STENCIL_BIT] = 0

            end

            this.render_target = render.render_target("", this.buffers)
        end,

        resize = function(this, width, height)
            if (width > 0 and height > 0) then
                this.width = width
                this.height = height
                render.set_render_target_size(this.render_target, width, height)
            end
        end,

        clear = function(this)
            render.clear(this.clear_buffers)
        end,

        enable = function(this)
            render.set_render_target(this.render_target)
        end
    }

    this:init()
    return this
end

return RenderTarget
