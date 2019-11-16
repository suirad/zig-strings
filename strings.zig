const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const testing = std.testing;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

/// String struct; compatible with c-style strings
pub const String = struct {
    bytes: []const u8 = "\x00",
    allocator: ?*Allocator = null,

    // Initialization

    /// Init with const []u8 slice; Slice must end with a null;
    pub fn init(slice: []const u8) !String {
        if (slice.len == 0) {
            return error.EmptySlice;
        }
        if (slice[slice.len - 1] != 0) {
            return error.NotNullTerminated;
        }
        return String{ .bytes = slice };
    }

    /// Meant to be compatible with c"" text
    pub fn initCstr(ptr: [*]const u8) !String {
        const length = mem.len(u8, ptr);
        if (length == 0) {
            return error.EmptySlice;
        }

        const result = ptr[0 .. length + 1];
        if (result[result.len - 1] != 0) {
            return error.NotNullTerminated;
        }

        return String{ .bytes = result };
    }

    /// Init with pre allocated []u8
    /// String assumes ownership and will free given []u8 with given allocator
    pub fn fromOwnedSlice(alloc: *Allocator, slice: []u8) !String {
        if (slice.len == 0) {
            return error.EmptySlice;
        }
        if (slice[slice.len - 1] != 0) {
            return error.NotNullTerminated;
        }
        return String{
            .bytes = slice,
            .allocator = alloc,
        };
    }

    /// Init with given slice, copied using given allocator
    pub fn fromSlice(alloc: *Allocator, slice: []const u8) !String {
        if (slice.len == 0) {
            return error.EmptySlice;
        }
        const copy = if (slice.len > 0 and slice[slice.len - 1] != 0)
            try alloc.alloc(u8, slice.len + 1)
        else
            try alloc.alloc(u8, slice.len);

        mem.copy(u8, copy, slice);
        if (copy.len > slice.len) {
            copy[slice.len] = 0;
        }
        return String{
            .bytes = copy,
            .allocator = alloc,
        };
    }

    /// Init with given String, copied using given allocator
    pub fn initCopy(alloc: *Allocator, other: *const String) !String {
        return try fromSlice(alloc, other.bytes);
    }

    // Destruction

    /// Free string if allocator is provided
    /// This fn is destructive and resets the state of the string to prevent use after being freed
    /// Requires the String to be mutable
    pub fn deinit(self: *String) void {
        self.deinitComptime();
        self.allocator = null;
        self.bytes = "\x00";
    }

    /// Free string if allocator is provided
    pub fn deinitComptime(self: *const String) void {
        if (self.allocator) |alloc| {
            alloc.free(self.bytes);
        }
    }

    pub fn deinitArrayList(list: ArrayList(String)) void {
        defer list.deinit();
        for (list.toSlice()) |*str| {
            str.deinit();
        }
    }

    // Utilities

    /// Get length of string, assumes last byte is null
    pub fn len(self: *const String) usize {
        return self.bytes.len - 1;
    }

    /// Returns slice of []u8 owned by this String
    /// Slice excludes null terminator
    pub fn toSlice(self: *const String) []const u8 {
        return self.bytes[0..self.len()];
    }

    /// Returns Owned slice of String contents, including null terminator
    /// String is reset at this point and no longer tracks the slice
    pub fn toOwnedSlice(self: *String) []const u8 {
        const ret = self.bytes;
        self.bytes = "";
        self.allocator = null;
        return ret;
    }

    /// Returns a [*]const u8 of the string, can be passed to c functions
    pub fn cstr(self: *const String) [*]const u8 {
        return self.bytes.ptr;
    }

    /// Compares two strings
    /// Return values are -1, 0, 1
    /// Target String only considers content and not trailing null
    pub fn cmp(self: *const String, other: String) i8 {
        return self.cmpSlice(other.bytes[0..other.len()]);
    }

    /// Compares a slice to a string
    /// String only considers content and not trailing null
    pub fn cmpSlice(self: *const String, slice: []const u8) i8 {
        return switch (mem.compare(u8, self.bytes[0..self.len()], slice)) {
            mem.Compare.Equal => 0,
            mem.Compare.GreaterThan => 1,
            mem.Compare.LessThan => -1,
        };
    }

    /// Checks for string equality
    pub fn eql(self: *const String, slice: String) bool {
        return if (self.cmp(slice) == 0) true else false;
    }

    pub fn eqlSlice(self: *const String, other: []const u8) bool {
        return if (self.cmpSlice(other) == 0) true else false;
    }

    /// Duplicate a string
    pub fn dupe(self: *const String) !String {
        if (self.allocator) |alloc| {
            return fromSlice(alloc, self.bytes);
        }
        return error.NoAllocator;
    }

    /// Duplicate a string, with a specific allocator
    pub fn dupeWith(self: *const String, alloc: *Allocator) !String {
        return fromSlice(alloc, self.bytes);
    }

    /// Concat two strings, using the allocator of the first
    pub fn concat(self: *const String, other: String) !String {
        return self.concatSlice(other.bytes[0..other.len()]);
    }

    /// Concat a string and a slice, using the allocator of the first
    pub fn concatSlice(self: *const String, slice: []const u8) !String {
        if (self.allocator) |alloc| {
            return self.concatSliceWithAllocator(slice, alloc);
        }
        return error.NoAllocator;
    }

    /// Concat a string and a slice, using the given allocator
    pub fn concatSliceWithAllocator(self: *const String, slice: []const u8, alloc: *Allocator) !String {
        const newlen = self.len() + slice.len;
        const result = try alloc.alloc(u8, newlen + 1);
        mem.copy(u8, result, self.bytes);
        mem.copy(u8, result[self.len()..], slice);
        result[newlen] = 0;
        return String{
            .bytes = result,
            .allocator = self.allocator,
        };
    }

    /// Find a string within a given string
    pub fn find(self: *const String, other: String) ?usize {
        return self.findSlice(other.bytes);
    }

    /// Find a slice within a given string
    pub fn findSlice(self: *const String, slice: []const u8) ?usize {
        return mem.indexOf(u8, self.bytes, slice);
    }

    /// Split string on a space
    pub fn split(self: *const String) !ArrayList(String) {
        return self.splitAt(" ");
    }

    /// Split string on given slice
    pub fn splitAt(self: *const String, slice: []const u8) !ArrayList(String) {
        if (slice.len == 0) {
            return error.EmptySlice;
        }
        if (self.allocator) |alloc| {
            return self.splitWithAllocator(slice, alloc);
        }
        return error.NoAllocator;
    }

    /// Split on given slice using given allocator
    pub fn splitWithAllocator(self: *const String, slice: []const u8, alloc: *Allocator) !ArrayList(String) {
        if (slice.len == 0) {
            return error.EmptySlice;
        }

        var selfitr = self.toSlice();
        var index = mem.indexOf(u8, selfitr, slice);
        if (index == null) {
            return error.SliceNotFound;
        }

        var list = ArrayList(String).init(alloc);
        errdefer list.deinit();

        while (index != null) : ({
            selfitr = selfitr[index.? + slice.len .. selfitr.len];
            index = mem.indexOf(u8, selfitr, slice);
        }) {
            const part = selfitr[0..index.?];
            if (part.len > 0) {
                const substr = try String.fromSlice(alloc, part);
                try list.append(substr);
            }
        }
        if (selfitr.len > 0) {
            const substr = try String.fromSlice(alloc, selfitr);
            try list.append(substr);
        }

        return list;
    }

    /// Join an ArrayList of strings into a single string with a delimiter
    /// Uses the list's allocator
    pub fn join(list: ArrayList(String), delim: []const u8) !String {
        return String.joinWith(list.allocator, list, delim);
    }

    /// Join an ArrayList of strings into a single string with a delimiter
    /// Uses the given allocator
    pub fn joinWith(alloc: *Allocator, list: ArrayList(String), delim: []const u8) !String {
        var total_len: usize = 0;
        const lslice = list.toSlice();
        for (lslice) |str, i| {
            total_len += str.len();
            if (i > 0 and i != list.len) {
                total_len += delim.len;
            }
        }

        const result = try alloc.alloc(u8, total_len + 1);
        errdefer alloc.free(result);
        result[total_len] = 0;

        var index: usize = 0;
        for (lslice) |str, i| {
            if (delim.len > 0 and i > 0 and i != list.len) {
                mem.copy(u8, result[index..], delim);
                index += delim.len;
            }

            const sslice = str.toSlice();
            mem.copy(u8, result[index..], sslice);
            index += sslice.len;
        }

        return String{
            .bytes = result,
            .allocator = alloc,
        };
    }
};

test "string initialization" {
    const allocator = std.heap.direct_allocator;

    // init bare struct
    var str1 = String{};
    defer str1.deinit();

    // init with string, manually terminated
    const raw_str2 = "String2\x00";
    var str2 = try String.init(raw_str2);
    defer str2.deinit();
    testing.expect(str2.len() == 7);
    // check null terminator
    testing.expect(str2.bytes[str2.len()] == 0);

    const raw_str3 = c"String3";
    var str3 = try String.initCstr(raw_str3);
    defer str3.deinit();
    testing.expect(str3.len() == 7);
    // check null terminator
    testing.expect(str3.bytes[str3.len()] == 0);

    // error trying to init from empty slice
    testing.expectError(error.EmptySlice, String.fromSlice(allocator, ""));

    // init copy of text
    var str4 = try String.fromSlice(allocator, "String4");
    defer str4.deinit();

    // init from preallocated owned slice
    const msg = try allocator.alloc(u8, 8);
    mem.copy(u8, msg, "String5\x00");
    var str5 = try String.fromOwnedSlice(allocator, msg);
    defer str5.deinit();

    // init copy of other string
    var str6 = try String.initCopy(allocator, &str4);
    defer str6.deinit();
}

test "to Owned slice" {
    const alloc = std.heap.direct_allocator;

    const buf = try alloc.alloc(u8, 10);
    buf[9] = 0;
    var str = try String.fromOwnedSlice(alloc, buf);
    const buf2 = str.toOwnedSlice();
    defer alloc.free(buf2);

    testing.expect(buf.ptr == buf2.ptr);
    testing.expect(str.allocator == null);
    testing.expect(mem.compare(u8, str.bytes, "") == mem.Compare.Equal);
}

test "String compare and equals" {
    const alloc = std.heap.direct_allocator;

    var str1 = try String.fromSlice(alloc, "CompareMe");
    var str2 = try String.fromSlice(alloc, "CompareMe");
    var str3 = try String.fromSlice(alloc, "COMPAREME");
    defer str1.deinit();
    defer str2.deinit();
    defer str3.deinit();

    // test cmp
    testing.expect(str1.cmpSlice("CompareMe") == 0);
    testing.expect(str1.cmp(str2) == 0);
    testing.expect(str1.cmpSlice("COMPAREME") == 1);
    testing.expect(str1.cmp(str3) == 1);

    // test eql
    testing.expect(str1.eqlSlice("CompareMe"));
    testing.expect(str1.eql(str2));
    testing.expect(str1.eql(str3) == false);
}

test "String duplication" {
    const alloc = std.heap.direct_allocator;

    var str1 = try String.fromSlice(alloc, "Dupe me");
    var str2 = try str1.dupe();
    defer str1.deinit();
    defer str2.deinit();

    testing.expect(str1.eql(str2));
    testing.expect(str1.bytes.ptr != str2.bytes.ptr);
}

test "String concatenation" {
    const alloc = std.heap.direct_allocator;

    var str1 = try String.fromSlice(alloc, "Con");
    var str2 = try String.fromSlice(alloc, "Cat");
    var str3 = try str1.concat(str2);
    var str4 = try str3.concatSlice("ing");

    testing.expect(str3.eqlSlice("ConCat"));
    testing.expect(str4.eqlSlice("ConCating"));

    str1.deinit();
    str2.deinit();
    str3.deinit();
    str4.deinit();
}

test "String finding" {
    const alloc = std.heap.direct_allocator;
    var str = try String.fromSlice(alloc, "The cow jumped over the moon.");
    var str2 = try String.fromSlice(alloc, "moon.");
    defer str.deinit();
    defer str.deinit();

    testing.expect(str.findSlice("The").? == 0);
    testing.expect(str.findSlice("the").? == 20);
    testing.expect(str.findSlice("cat") == null);
    testing.expect(str.find(str2).? == 24);
}

test "String Splitting" {
    const alloc = std.heap.direct_allocator;
    var str = try String.fromSlice(alloc, " Please Split me 5 times ");
    defer str.deinit();

    testing.expectError(error.EmptySlice, str.splitAt(""));
    testing.expectError(error.SliceNotFound, str.splitAt("Blah"));
    var splitstr: ArrayList(String) = try str.split();
    defer String.deinitArrayList(splitstr);

    for (splitstr.toSlice()) |val, i| {
        switch (i) {
            0 => testing.expect(val.eqlSlice("Please")),
            1 => testing.expect(val.eqlSlice("Split")),
            2 => testing.expect(val.eqlSlice("me")),
            3 => testing.expect(val.eqlSlice("5")),
            4 => testing.expect(val.eqlSlice("times")),
            else => return error.BadIndex,
        }
    }

    var str2 = try String.fromSlice(alloc, "Thic|=|Splitting");
    defer str2.deinit();

    var splitstr2 = try str2.splitAt("|=|");
    defer String.deinitArrayList(splitstr2);

    testing.expect(splitstr2.at(0).eqlSlice("Thic"));
    testing.expect(splitstr2.at(1).eqlSlice("Splitting"));
}

test "String Joining" {
    const alloc = std.heap.direct_allocator;
    var list = ArrayList(String).init(alloc);
    defer String.deinitArrayList(list);

    var str1 = try String.fromSlice(alloc, "Hello");
    var str2 = try String.fromSlice(alloc, "New");
    var str3 = try String.fromSlice(alloc, "World!");

    try list.append(str1);
    try list.append(str2);
    try list.append(str3);

    var jstr1 = try String.join(list, " ");
    var jstr2 = try String.join(list, "");
    var jstr3 = try String.join(list, "===");
    defer jstr1.deinit();
    defer jstr2.deinit();
    defer jstr3.deinit();

    testing.expect(jstr1.eqlSlice("Hello New World!"));
    testing.expect(jstr2.eqlSlice("HelloNewWorld!"));
    testing.expect(jstr3.eqlSlice("Hello===New===World!"));
}
