pub const Tables = enum {
    dummy,
};

pub const TableFields = struct {
    dummy: void,
};

pub const TableFieldsUnion = union(Tables) {
    dummy: void,

    pub fn toString(self: @This()) []const u8 {
        _ = self;
        return "dummy";
    }
};
