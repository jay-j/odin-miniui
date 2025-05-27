package handle

// From Karl Zylinski:
// https://gist.github.com/karl-zylinski/a5c6acd551473f90b872f46a2fa58deb
// This is array/index-backed (rather than hash map-backed) so performance is expected
// to be better (vs. map-based) with dense arrays.
// A better-performing strategy (https://github.com/jakubtomsu/sds/blob/main/pool.odin)
// was not chosen since it requires a size limit to be assigned at the start.

Handle :: struct {
	idx: u32,
	gen: u32,
}

HANDLE_NONE :: Handle{}

// Usage:
// Entity_Handle :: distinct Handle
// entities: Handle_Array(Entity, Entity_Handle)
// the Entity struct must contain a field "handle: Entity_Handle"
Handle_Array :: struct($T: typeid, $HT: typeid) {
	items:    [dynamic]T,
	freelist: [dynamic]HT,
	num:      int, // Quantity of *active* items (not item capacity)
}


// User is expected to declare the Handle Array so it get assigned the correct polymorphic types
// Assign allocators and reserves initial size on them
init :: proc(ha: ^Handle_Array($T, $HT), qty_reserve: int = 16, allocator := context.allocator) {
	ha.items.allocator = allocator
	ha.freelist.allocator = allocator
	reserve(&ha.items, qty_reserve)
	reserve(&ha.freelist, qty_reserve / 2)
}


// Release all the backing memory for the Handle Array
destroy :: proc(ha: ^Handle_Array($T, $HT)) {
	delete(ha.items)
	delete(ha.freelist)
}


// Clear memory and start over with the Handle Array
reset :: proc(ha: ^Handle_Array($T, $HT)) {
	clear(&ha.items)
	clear(&ha.freelist)
	ha.num = 0
}


add :: proc(ha: ^Handle_Array($T, $HT), v: T) -> HT {
	v := v

	// Prioritze re-using old slots
	if len(ha.freelist) > 0 {
		h := pop(&ha.freelist)
		h.gen += 1
		v.handle = h
		ha.items[h.idx] = v
		ha.num += 1
		return h
	}

	// If this Handle_Array has never been used before, make a 
	// dummy item at index zero for zero comparison
	if len(ha.items) == 0 {
		append_nothing(&ha.items)
	}

	// Append new items to the Handle_Array
	idx := u32(len(ha.items))
	v.handle.idx = idx
	v.handle.gen = 1
	append(&ha.items, v)
	ha.num += 1
	return v.handle
}


// Get the element using its handle
// PERFORMANCE: Is this performing array bounds checks twice?
get :: proc(ha: Handle_Array($T, $HT), h: HT) -> (T, bool) {
	if h.idx > 0 && int(h.idx) < len(ha.items) && ha.items[h.idx].handle == h {
		return ha.items[h.idx], true
	}
	return {}, false
}


// Get a pointer to the element using its handle
// Returns nil if the requested handle is not found
get_ptr :: proc(ha: Handle_Array($T, $HT), h: HT) -> ^T {
	if h.idx > 0 && int(h.idx) < len(ha.items) && ha.items[h.idx].handle == h {
		return &ha.items[h.idx]
	}
	return nil
}


remove :: proc(ha: ^Handle_Array($T, $HT), h: HT) {
	if h.idx > 0 && int(h.idx) < len(ha.items) && ha.items[h.idx].handle == h {
		append(&ha.freelist, h)
		ha.items[h.idx] = {}
		ha.num -= 1
	}
}


valid :: proc(ha: ^Handle_Array($T, $HT), h: HT) -> bool {
	return get(ha, h) != nil
}


// Iterators for iterating over all active slots in the items array
// Usage:
// array_iter := make_iter(my_handle_array)
// for v in ha_iter_ptr(&array_iter)


// The iterator can use a shallow copy of the Handle_Array, because
// the same memory is pointed to, and users won't use the iterator to
// add/remove elements from the array.
Handle_Array_Iter :: struct($T: typeid, $HT: typeid) {
	ha:    Handle_Array(T, HT),
	index: int,
}


make_iter :: proc(h: Handle_Array($T, $HT)) -> Handle_Array_Iter(T, HT) {
	return Handle_Array_Iter(T, HT){ha = h}
}


// Call repeatedly in a for loop to iterate through, get values
iter :: proc(it: ^Handle_Array_Iter($T, $HT)) -> (val: T, h: HT, found: bool) {
	continue_search := it.index < len(it.ha.items)

	for continue_search {
		found = it.index > 0 && continue_search && it.ha.items[it.index].handle.idx > 0

		if found {
			val = it.ha.items[it.index]
			h = it.ha.items[it.index].handle
			it.index += 1 // for the next iter() call
			return
		}

		it.index += 1
		continue_search = it.index < len(it.ha.items)
	}
	return
}


// Call repeatedly in a for loop to iterate through, get pointers to elements
iter_ptr :: proc(it: ^Handle_Array_Iter($T, $HT)) -> (val: ^T, h: HT, found: bool) {
	continue_search := it.index < len(it.ha.items)

	for continue_search {
		found = it.index > 0 && continue_search && it.ha.items[it.index].handle.idx > 0

		if found {
			val = &it.ha.items[it.index]
			h = it.ha.items[it.index].handle
			it.index += 1 // for the next iter() call
			return
		}

		it.index += 1
		continue_search = it.index < len(it.ha.items)
	}
	return
}
