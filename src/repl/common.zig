const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

pub const arrows_widget = vxfw.Text{
    .text = ">> ",
    .softwrap = false,
    .overflow = .clip,
};
