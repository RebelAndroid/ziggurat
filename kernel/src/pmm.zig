pub const FrameAllocator = struct {
    front: u64 = 0,
    hhdm_offset: u64,
    pub fn free_frames(self: *FrameAllocator, start: u64, size: u64) void {
        if (self.front == 0) {
            // linked list is empty
            self.front = start;
            const node = FrameAllocatorNode{
                .size = size,
                .next = 0,
            };
            const node_ptr: *FrameAllocatorNode = @ptrFromInt(start + self.hhdm_offset);
            node_ptr.* = node;
        } else {
            const node = FrameAllocatorNode{
                .size = size,
                .next = self.front,
            };
            const node_ptr: *FrameAllocatorNode = @ptrFromInt(start + self.hhdm_offset);
            node_ptr.* = node;
            // add the new node to the front of the list
            self.front = start;
        }
    }
    pub fn allocate_frame(self: *FrameAllocator) u64 {
        if (self.front == 0) {
            // linked list is empty, big sad
            return 0; // TODO: actual errors?
        }
        const node_ptr: *FrameAllocatorNode = @ptrFromInt(self.front + self.hhdm_offset);
        node_ptr.size -= 1;
        // return the last frame in this node
        const out = self.front + 0x1000 * node_ptr.size;
        if (node_ptr.size == 0) {
            // if the node has no more pages left, remove it
            self.front = node_ptr.next;
        }
        return out;
    }
};
const FrameAllocatorNode = packed struct {
    size: u64 = 0,
    next: u64 = 0,
};
