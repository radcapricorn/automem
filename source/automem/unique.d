module automem.unique;

import automem.test_utils: TestUtils;
import automem.traits: isAllocator;
import std.experimental.allocator: theAllocator;

version(unittest) {
    import unit_threaded;
    import test_allocator: TestAllocator;
}

mixin TestUtils;

struct Unique(Type, Allocator = typeof(theAllocator())) if(isAllocator!Allocator) {

    import std.traits: hasMember;
    import std.typecons: Proxy;

    enum isSingleton = hasMember!(Allocator, "instance");
    enum isTheAllocator = is(Allocator == typeof(theAllocator));
    enum isGlobal = isSingleton || isTheAllocator;

    static if(is(Type == class))
        alias Pointer = Type;
    else
        alias Pointer = Type*;

    static if(isGlobal) {

        /**
           The allocator is global, so no need to pass it in to the constructor
        */
        this(Args...)(auto ref Args args) {
            this.makeObject!args();
        }

    } else {

        /**
           Non-singleton allocator, must be passed in
         */

        this(Args...)(Allocator allocator, auto ref Args args) {
            _allocator = allocator;
            this.makeObject!args();
        }
    }


    this(T)(Unique!(T, Allocator) other) if(is(T: Type)) {
        moveFrom(other);
    }

    @disable this(this);

    ~this() {
        deleteObject;
    }

    /**
       Gets the owned pointer. Use with caution.
     */
    inout(Pointer) get() inout @system {
        return _object;
    }

    /**
       Releases ownership and transfers it to the returned
       Unique object.
     */
    Unique unique() {
        import std.algorithm: move;
        Unique u;
        move(this, u);
        assert(_object is null);
        return u;
    }

    package Pointer release() {
        auto ret = _object;
        _object = null;
        return ret;
    }

    package Allocator allocator() {
        return _allocator;
    }

    /**
       "Truthiness" cast
     */
    bool opCast(T)() const if(is(T == bool)) {
        return _object !is null;
    }

    void opAssign(T)(Unique!(T, Allocator) other) if(is(T: Type)) {
        deleteObject;
        moveFrom(other);
    }

    mixin Proxy!_object;

private:

    Pointer _object;

    static if(isSingleton)
        alias _allocator = Allocator.instance;
    else static if(isTheAllocator)
        alias _allocator = theAllocator;
    else
        Allocator _allocator;

    void deleteObject() @safe {
        import std.experimental.allocator: dispose;
        import std.traits: isPointer;

        static if(isPointer!Allocator)
            assert(_object is null || _allocator !is null);

        if(_object !is null) () @trusted { _allocator.dispose(_object); }();
    }

    void moveFrom(T)(ref Unique!(T, Allocator) other) if(is(T: Type)) {
        _object = other._object;
        other._object = null;

        static if(!isGlobal) {
            import std.algorithm: move;
            _allocator = other._allocator.move;
        }
    }
}

private template makeObject(args...)
{
    void makeObject(Type,A)(ref Unique!(Type, A) u) {
        import std.experimental.allocator: make;
        import std.functional : forward;
        version(LDC)
            u._object = () @trusted { return u._allocator.make!Type(forward!args); }();
        else
            u._object = u._allocator.make!Type(forward!args);
    }
}

@("with struct and test allocator")
@system unittest {

    auto allocator = TestAllocator();
    {
        const foo = Unique!(Struct, TestAllocator*)(&allocator, 5);
        foo.twice.shouldEqual(10);
        allocator.numAllocations.shouldEqual(1);
        Struct.numStructs.shouldEqual(1);
    }

    Struct.numStructs.shouldEqual(0);
}

@("with class and test allocator")
@system unittest {

    auto allocator = TestAllocator();
    {
        const foo = Unique!(Class, TestAllocator*)(&allocator, 5);
        foo.twice.shouldEqual(10);
        allocator.numAllocations.shouldEqual(1);
        Class.numClasses.shouldEqual(1);
    }

    Class.numClasses.shouldEqual(0);
}


@("with struct and mallocator")
@system unittest {

    import std.experimental.allocator.mallocator: Mallocator;
    {
        const foo = Unique!(Struct, Mallocator)(5);
        foo.twice.shouldEqual(10);
        Struct.numStructs.shouldEqual(1);
    }

    Struct.numStructs.shouldEqual(0);
}


@("default constructor")
@system unittest {
    auto allocator = TestAllocator();

    auto ptr = Unique!(Struct, TestAllocator*)();
    (cast(bool)ptr).shouldBeFalse;
    ptr.get.shouldBeNull;

    ptr = Unique!(Struct, TestAllocator*)(&allocator, 5);
    ptr.get.shouldNotBeNull;
    ptr.get.twice.shouldEqual(10);
    (cast(bool)ptr).shouldBeTrue;
}

@(".init")
@system unittest {
    auto allocator = TestAllocator();

    Unique!(Struct, TestAllocator*) ptr;
    (cast(bool)ptr).shouldBeFalse;
    ptr.get.shouldBeNull;

    ptr = Unique!(Struct, TestAllocator*)(&allocator, 5);
    ptr.get.shouldNotBeNull;
    ptr.get.twice.shouldEqual(10);
    (cast(bool)ptr).shouldBeTrue;
}

@("move")
@system unittest {
    import std.algorithm: move;

    auto allocator = TestAllocator();
    auto oldPtr = Unique!(Struct, TestAllocator*)(&allocator, 5);
    Unique!(Struct, TestAllocator*) newPtr = oldPtr.move;
    oldPtr.shouldBeNull;
    newPtr.twice.shouldEqual(10);
    Struct.numStructs.shouldEqual(1);
}

@("copy")
@system unittest {
    auto allocator = TestAllocator();
    auto oldPtr = Unique!(Struct, TestAllocator*)(&allocator, 5);
    Unique!(Struct, TestAllocator*) newPtr;
    // non-copyable
    static assert(!__traits(compiles, newPtr = oldPtr));
}

@("construct base class")
@system unittest {
    auto allocator = TestAllocator();
    {
        Unique!(Object, TestAllocator*) bar = Unique!(Class, TestAllocator*)(&allocator, 5);
        Class.numClasses.shouldEqual(1);
    }

    Class.numClasses.shouldEqual(0);
}

@("assign base class")
@system unittest {
    auto allocator = TestAllocator();
    {
        Unique!(Object, TestAllocator*) bar;
        bar = Unique!(Class, TestAllocator*)(&allocator, 5);
        Class.numClasses.shouldEqual(1);
    }

    Class.numClasses.shouldEqual(0);
}

@("Return Unique from function")
@system unittest {
    auto allocator = TestAllocator();

    auto produce(int i) {
        return Unique!(Struct, TestAllocator*)(&allocator, i);
    }

    auto ptr = produce(4);
    ptr.twice.shouldEqual(8);
}

@("unique")
@system unittest {
    auto allocator = TestAllocator();
    auto oldPtr = Unique!(Struct, TestAllocator*)(&allocator, 5);
    auto newPtr = oldPtr.unique;
    newPtr.twice.shouldEqual(10);
    oldPtr.shouldBeNull;
}

@("@nogc")
@system @nogc unittest {

    import std.experimental.allocator.mallocator: Mallocator;

    {
        const ptr = Unique!(NoGcStruct, Mallocator)(5);
        // shouldEqual isn't @nogc
        assert(ptr.i == 5);
        assert(NoGcStruct.numStructs == 1);
    }

    assert(NoGcStruct.numStructs == 0);
}

@("@nogc @safe")
@safe @nogc unittest {

    auto allocator = SafeAllocator();

    {
        const ptr = Unique!(NoGcStruct, SafeAllocator)(SafeAllocator(), 6);
        // shouldEqual isn't @nogc
        assert(ptr.i == 6);
        assert(NoGcStruct.numStructs == 1);
    }

    assert(NoGcStruct.numStructs == 0);
}

@("deref")
@system unittest {
    {
        auto allocator = TestAllocator();
        auto ptr = Unique!(Struct, TestAllocator*)(&allocator, 5);
        *ptr = Struct(13);
        ptr.twice.shouldEqual(26);
        Struct.numStructs.shouldEqual(1);
    }
    Struct.numStructs.shouldEqual(0);
}

@("move from populated other unique")
@system unittest {

    import std.algorithm: move;

    {
        auto allocator = TestAllocator();

        auto ptr1 = Unique!(Struct, TestAllocator*)(&allocator, 5);
        Struct.numStructs.shouldEqual(1);

        {
            auto ptr2 = Unique!(Struct, TestAllocator*)(&allocator, 10);
            Struct.numStructs.shouldEqual(2);
            ptr1 = ptr2.move;
            Struct.numStructs.shouldEqual(1);
            ptr2.shouldBeNull;
            ptr1.twice.shouldEqual(20);
        }

    }

    Struct.numStructs.shouldEqual(0);
}

@("assign to rvalue")
@system unittest {

    import std.algorithm: move;

    {
        auto allocator = TestAllocator();

        auto ptr = Unique!(Struct, TestAllocator*)(&allocator, 5);
        ptr = Unique!(Struct, TestAllocator*)(&allocator, 7);

        Struct.numStructs.shouldEqual(1);
        ptr.twice.shouldEqual(14);
    }

    Struct.numStructs.shouldEqual(0);
}


@("theAllocator")
@system unittest {
    import std.experimental.allocator: allocatorObject, dispose;

    auto allocator = TestAllocator();
    auto oldAllocator = theAllocator;
    scope(exit) {
        allocator.dispose(theAllocator);
        theAllocator = oldAllocator;
    }
    theAllocator = allocatorObject(allocator);

    {
        auto ptr = Unique!Struct(42);
        (*ptr).shouldEqual(Struct(42));
        Struct.numStructs.shouldEqual(1);
    }

    Struct.numStructs.shouldEqual(0);
}
