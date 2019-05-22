#!python
#cython: language_level=3

import copy

cimport cyquant.ctypes as c
cimport cyquant.dimensions as d
import cyquant.dimensions as d

from libc.math cimport fabs

cdef double UNIT_SCALE_RTOL = 1e-12

cdef class SIUnit:


    @staticmethod
    def SetEqRelTol(double rtol):
        global UNIT_SCALE_RTOL
        if rtol < 0:
            raise ValueError("Relative tolerance must be greater than 0.")
        UNIT_SCALE_RTOL = rtol

    @staticmethod
    def GetEqRelTol():
        return UNIT_SCALE_RTOL

    @staticmethod
    def Unit(scale=1, kg=0, m=0, s=0, k=0, a=0, mol=0, cd=0):
        return SIUnit(scale, d.Dimensions(kg, m, s, k, a, mol, cd))

    @property
    def scale(self):
        return self.data.scale

    @property
    def dimensions(self):
        cdef d.Dimensions dims = d.Dimensions.__new__(d.Dimensions)
        dims.data = self.data.dimensions
        return dims

    @property
    def kg(self):
        return self.data.dimensions.exponents[0]

    @property
    def m(self):
        return self.data.dimensions.exponents[1]

    @property
    def s(self):
        return self.data.dimensions.exponents[2]

    @property
    def k(self):
        return self.data.dimensions.exponents[3]

    @property
    def a(self):
        return self.data.dimensions.exponents[4]

    @property
    def mol(self):
        return self.data.dimensions.exponents[5]

    @property
    def cd(self):
        return self.data.dimensions.exponents[6]

    def __init__(SIUnit self, double scale=1.0, d.Dimensions dims=d.dimensionless_t):
        if scale <= 0:
            raise ValueError("arg 'scale' must be greater than 0")
        if type(dims) is not d.Dimensions:
            raise TypeError("Expected Dimensions")
        self.data.scale = scale
        self.data.dimensions = dims.data

    """
    Wrapping Methods
    """

    def pack(SIUnit self, *args):
        return self.quantities(args)

    def unpack(SIUnit self, *args):
        return self.values(args)

    def quantities(SIUnit self, iterable):
        for value in iterable:
            yield self.promote(value)

    def values(SIUnit self, iterable):
        for quantity in iterable:
            yield self.demote(quantity)

    cpdef promote(SIUnit self, object value):
        if value is None:
            raise TypeError("Quantity value can not be None.")

        cdef Quantity ret = Quantity.__new__(Quantity)
        ret.udata = self.data

        cdef type value_type = type(value)
        if value_type is float or value_type is int:
            ret.c_value = value
            ret.py_value = None
        else:
            ret.py_value = value

        return ret

    cpdef demote(SIUnit self, Quantity value):
        if value is None:
            raise TypeError("Expected Quantity")

        if value.py_value is None:
            return value.c_value * value.rescale(self.data)
        return value.py_value * value.rescale(self.data)


    def __call__(SIUnit self, iterable):
        return self.quantities(iterable)

    """
    Comparison Methods
    """

    cpdef is_of(SIUnit self, d.Dimensions dims):
        if dims is None:
            raise TypeError()
        return c.eq_ddata(self.data.dimensions, dims.data)

    def __eq__(lhs, rhs):
        if not type(lhs) is SIUnit:
            return NotImplemented
        if not type(rhs) is SIUnit:
            return NotImplemented
        return lhs.approx(rhs, rtol=UNIT_SCALE_RTOL)

    def __ne__(lhs, rhs):
        return not lhs == rhs

    def __lt__(SIUnit lhs not None, SIUnit rhs not None):
        return lhs.cmp(rhs) < 0

    def __le__(SIUnit lhs not None, SIUnit rhs not None):
        return lhs.cmp(rhs) <= 0

    def __gt__(SIUnit lhs not None, SIUnit rhs not None):
        return lhs.cmp(rhs) > 0

    def __ge__(SIUnit lhs not None, SIUnit rhs not None):
        return lhs.cmp(rhs) >= 0


    cpdef cmp(SIUnit self, SIUnit other):
        cdef int signum, error_code
        error_code = c.cmp_udata(signum, self.data, other.data)
        if error_code == c.Success:
            return signum

        if error_code == c.DimensionMismatch:
            raise ValueError("units mismatch")

        raise RuntimeError("Unknown Error Occurred: %i" % error_code)

    cpdef approx(SIUnit self, SIUnit other, double rtol=1e-9, double atol=0.0):
        if not self.compatible(other):
            raise ValueError("unit mismatch")
        return c.fapprox(self.data.scale, other.data.scale, rtol, atol)

    cpdef bint compatible(SIUnit self, SIUnit other):
        return c.eq_ddata(self.data.dimensions, other.data.dimensions)

    """
    Arithmetic Methods
    """

    def __mul__(lhs not None, rhs not None):
        cdef type op_lhs = type(lhs)
        cdef type op_rhs = type(rhs)

        if op_lhs is Quantity or op_rhs is Quantity:
            return NotImplemented

        if op_lhs is SIUnit and op_rhs is SIUnit:
            return mul_units(lhs, rhs)

        if op_lhs is SIUnit:
            return lhs.promote(rhs)
        if op_rhs is SIUnit:
            return rhs.promote(lhs)

        raise RuntimeError("unknown error")



    def __truediv__(lhs not None, rhs not None):
        cdef type op_lhs = type(lhs)
        cdef type op_rhs = type(rhs)

        if op_lhs is Quantity or op_rhs is Quantity:
            return NotImplemented

        if op_lhs is SIUnit and op_rhs is SIUnit:
            return div_units(lhs, rhs)

        cdef Quantity ret = Quantity.__new__(Quantity)

        if op_lhs is SIUnit:
            get_udata(ret.udata, lhs)

            if op_rhs is float or op_rhs is int:
                ret.py_value = None
                ret.c_value = rhs
            else:
                ret.py_value = rhs

        if op_rhs is SIUnit:
            get_udata(ret.udata, rhs)

            if op_lhs is float or op_lhs is int:
                ret.py_value = None
                ret.c_value = lhs
            else:
                ret.py_value = lhs

        if c.inv_udata(ret.udata, ret.udata) == c.Success:
            return ret

        raise RuntimeError("unknown error")


    def __invert__(SIUnit self):
        cdef c.Error error_code
        cdef SIUnit ret = SIUnit.__new__(SIUnit)
        error_code = c.inv_udata(ret.data, self.data)
        if error_code == c.Success:
            return ret

        if error_code == c.ZeroDiv:
            raise ZeroDivisionError()

        raise RuntimeError("Unknown Error Occurred: %i" % error_code)

    def __pow__(lhs, rhs, modulo):
        if type(lhs) is not SIUnit:
            raise TypeError("Expected SIUnit ** Number")
        return lhs.exp(rhs)

    cpdef SIUnit exp(SIUnit self, double power):
        cdef c.Error error_code
        cdef SIUnit ret = SIUnit.__new__(SIUnit)
        error_code = c.pow_udata(ret.data, self.data, power)
        if error_code == c.Success:
            return ret

        raise RuntimeError("Unknown Error Occurred: %i" % error_code)

    def __copy__(SIUnit self):
        return self

    def __deepcopy__(SIUnit self, dict memodict={}):
        return self

    def __hash__(SIUnit self):
        data_tuple = (self.data.scale, tuple(self.data.dimensions.exponents))
        return hash(data_tuple)

    def __repr__(SIUnit self):
        return 'SIUnit(%f, %r)' % (self.data.scale, self.dimensions)

cdef class Quantity:

    @property
    def quantity(self):
        if self.py_value:
            return self.py_value
        return self.c_value

    @property
    def q(self):
        return self.quantity

    @property
    def units(self):
        cdef SIUnit units = SIUnit.__new__(SIUnit)
        units.data = self.udata
        return units

    def __init__(Quantity self, object value, SIUnit units not None):
        self.udata = units.data
        type_value = type(value)
        if type_value is float or type_value is int:
            self.py_value = None
            self.c_value = value
        else:
            self.py_value = value

    cdef double rescale(Quantity self, const c.UData& units) except -1.0:
        if not c.eq_ddata(self.udata.dimensions, units.dimensions):
            raise ValueError("Incompatible unit dimensions")
        return self.udata.scale / units.scale

    cpdef is_of(Quantity self, d.Dimensions dims):
        if dims is None:
            raise TypeError("Expected Dimensions")
        return c.eq_ddata(self.udata.dimensions, dims.data)

    cpdef get_as(Quantity self, SIUnit units):
        if units is None:
            raise TypeError("Expected SIUnit")

        if self.py_value:
            return self.py_value * self.rescale(units.data)

        return self.c_value * self.rescale(units.data)

    cpdef round_as(Quantity self, SIUnit units):
        return round(self.get_as(units))

    cpdef Quantity cvt_to(Quantity self, SIUnit units):
        if units is None:
            raise TypeError("Expected SIUnit")


        if c.eq_udata(self.udata, units.data):
            return self

        cdef Quantity ret = Quantity.__new__(Quantity)
        ret.udata = units.data
        if self.py_value:
            ret.py_value = self.py_value * self.rescale(units.data)
        else:
            ret.py_value = None
            ret.c_value = self.c_value * self.rescale(units.data)

        return ret

    cpdef Quantity round_to(Quantity self, SIUnit units):
        if units is None:
            raise TypeError("Expected SIUnit")

        cdef Quantity ret = Quantity.__new__(Quantity)
        ret.udata = units.data
        if self.py_value is None:
            ret.py_value = None
            ret.c_value = round(self.c_value * self.rescale(units.data))
        else:
            ret.py_value = round(self.py_value * self.rescale(units.data))

        return ret

    """
    Comparison Methods
    """

    def __eq__(lhs, rhs):
        if type(lhs) is not Quantity:
            return NotImplemented
        if type(rhs) is not Quantity:
            return NotImplemented

        try:
            return lhs.cmp(rhs) == 0
        except ValueError:
            return NotImplemented

    def __ne__(lhs, rhs):
        return not lhs == rhs

    def __lt__(Quantity lhs not None, Quantity rhs not None):
        return lhs.cmp(rhs) < 0

    def __le__(Quantity lhs not None, Quantity rhs not None):
        return lhs.cmp(rhs) <= 0

    def __gt__(Quantity lhs not None, Quantity rhs not None):
        return lhs.cmp(rhs) > 0

    def __ge__(Quantity lhs not None, Quantity rhs not None):
        return lhs.cmp(rhs) >= 0

    cpdef cmp(Quantity self, Quantity other):
        if not c.eq_ddata(self.udata.dimensions, other.udata.dimensions):
            raise ValueError("Incompatible Dimensions")

        if self.py_value is None and other.py_value is None:
            return unsafe_native_cmp(self, other)

        cdef object lhs, rhs

        if self.py_value:
            lhs = self.py_value * self.udata.scale
        else:
            lhs = self.c_value * self.udata.scale

        if other.py_value:
            rhs = other.py_value * self.udata.scale
        else:
            rhs = other.c_value * self.udata.scale

        if lhs > rhs:
            return 1
        if lhs < rhs:
            return -1
        return 0


    cpdef bint compatible(Quantity self, Quantity other):
        return c.eq_ddata(self.udata.dimensions, other.udata.dimensions)


    cpdef r_approx(Quantity self, Quantity other, double rtol=1e-9):
        cdef int error_code
        cdef c.UData norm_udata
        cdef double self_norm, other_norm, epsilon

        error_code = c.min_udata(norm_udata, self.udata, other.udata)

        if error_code == c.Success:
            if self.py_value is None and other.py_value is None:
                return r_approx_d(self.c_value, self.udata, other.c_value, other.udata, rtol)

            return r_approx_o(
                self.c_value if self.py_value is None else self.py_value,
                self.udata,
                other.c_value if other.py_value is None else other.py_value,
                other.udata,
                rtol
            )

        if error_code == c.DimensionMismatch:
            raise ValueError("unit mismatch")

        raise RuntimeError("Unknown Error Occurred: %i" % error_code)


    """
    cpdef a_approx(Quantity self, Quantity other, double atol=1e-6):
        cdef int error_code
        cdef c.UData norm_udata
        cdef double self_norm, other_norm

        error_code = c.min_udata(norm_udata, self.data.units, other.data.units)
        if error_code == c.Success:
            self_norm = c.unsafe_extract_quantity(self.data, norm_udata)
            other_norm = c.unsafe_extract_quantity(other.data, norm_udata)
            return fabs(self_norm - other_norm) <= fabs(atol)

        if error_code == c.DimensionMismatch:
            raise ValueError("unit mismatch")

        raise RuntimeError("Unknown Error Occurred: %i" % error_code)


    cpdef q_approx(Quantity self, Quantity other, Quantity qtol):
        if self.py_value is None and other.py_value is None and qtol.py_value is None:
            return q_approx_d()

        cdef int error_code1, error_code2
        cdef double self_val, other_val
        error_code1 = c.extract_quantity(self_val, self.data, qtol.data.units)
        error_code2 = c.extract_quantity(other_val, other.data, qtol.data.units)

        if error_code1 | error_code2 == c.Success:
            return fabs(self_val - other_val) <= fabs(qtol.data.quantity)

        if error_code1 == c.DimensionMismatch:
            raise ValueError("unit mismatch (lhs)")
        if error_code2 == c.DimensionMismatch:
            raise ValueError("unit mismatch (rhs)")

        raise RuntimeError("Unknown Error Occurred: %i" % (error_code1 | error_code2))
    """


    """
    Arithmetic Methods
    """

    def __add__(Quantity lhs not None, Quantity rhs not None):
        cdef int error_code
        cdef Quantity ret = Quantity.__new__(Quantity)

        cdef double scale_l, scale_r

        error_code = c.min_udata(ret.udata, lhs.udata, rhs.udata)
        if error_code == c.Success:

            scale_l = lhs.udata.scale / ret.udata.scale
            scale_r = rhs.udata.scale / ret.udata.scale

            if lhs.py_value is None and rhs.py_value is None:
                ret.py_value = None
                ret.c_value = lhs.c_value * scale_l + rhs.c_value * scale_r
                return ret

            if lhs.py_value is None:
                ret.py_value = lhs.c_value * scale_l
            else:
                ret.py_value = lhs.py_value * scale_l

            if rhs.py_value is None:
                ret.py_value = ret.py_value + (rhs.c_value * scale_r)
            else:
                ret.py_value = ret.py_value + (rhs.py_value * scale_r)

            if q_norm(ret) == c.Success:
                return ret

        if error_code == c.DimensionMismatch:
            raise ValueError("unit mismatch")

        raise RuntimeError("Unknown Error Occurred: %i" % error_code)

    def __sub__(Quantity lhs not None, Quantity rhs not None):
        cdef int error_code
        cdef Quantity ret = Quantity.__new__(Quantity)

        cdef double scale_l, scale_r

        error_code = c.min_udata(ret.udata, lhs.udata, rhs.udata)
        if error_code == c.Success:
            scale_l = lhs.udata.scale / ret.udata.scale
            scale_r = rhs.udata.scale / ret.udata.scale

            if lhs.py_value is None and rhs.py_value is None:
                ret.py_value = None
                ret.c_value = lhs.c_value * scale_l
                ret.c_value = ret.c_value - (rhs.c_value * scale_r)
                return ret

            if lhs.py_value is None:
                ret.py_value = lhs.c_value * scale_l
            else:
                ret.py_value = lhs.py_value * scale_l

            if rhs.py_value is None:
                ret.py_value = ret.py_value - (rhs.c_value * scale_r)
            else:
                ret.py_value = ret.py_value - (rhs.py_value * scale_r)

            if q_norm(ret) == c.Success:
                return ret

        if error_code == c.DimensionMismatch:
            raise ValueError("unit mismatch")

        raise RuntimeError("Unknown Error Occurred: %i" % error_code)

    def __mul__(lhs not None, rhs not None):
        cdef Quantity ret = Quantity.__new__(Quantity)
        parse_q(ret, lhs)
        q_assign_mul(ret, rhs)
        return ret




    def __truediv__(lhs not None, rhs not None):
        cdef int error_code
        cdef Quantity ret = Quantity.__new__(Quantity)
        parse_q(ret, lhs)

        error_code = q_assign_div(ret, rhs)
        if error_code == c.Success:
            return ret

        if error_code == c.ZeroDiv:
            raise ZeroDivisionError()

        return RuntimeError("Unknown Error Occurred: %i" % error_code)

    def __pow__(lhs, rhs, modulo):
        if type(lhs) is not Quantity:
            raise TypeError("Expected Quantity ** Number")
        return lhs.exp(rhs)

    def __neg__(Quantity self):
        cdef Quantity ret = Quantity.__new__(Quantity)
        ret.udata = self.udata
        if self.py_value is None:
            ret.py_value = None
            ret.c_value = -self.c_value
        else:
            self.py_value = -self.c_value
        return ret

    def __invert__(Quantity self):
        cdef int error_code
        cdef Quantity ret = Quantity.__new__(Quantity)

        error_code = c.inv_udata(ret.udata, self.udata)

        if self.py_value is None:
            if self.c_value == 0:
                raise ZeroDivisionError()

            ret.py_value = None
            ret.c_value = 1.0 / self.c_value
        else:
            ret.py_value = 1.0 / self.py_value

        if error_code == c.Success:
            return ret

        raise RuntimeError("Unknown Error Occurred: %i" % error_code)

    def __abs__(Quantity self):
        cdef Quantity ret = Quantity.__new__(Quantity)
        ret.udata = self.udata

        if self.py_value is None:
            ret.py_value = None
            ret.c_value = fabs(self.c_value)
        else:
            ret.py_value = abs(self.py_value)
        return ret


    cpdef Quantity exp(Quantity self, double power):
        cdef Quantity ret = Quantity.__new__(Quantity)

        cdef error_code = c.pow_udata(ret.udata, self.udata, power)
        if error_code != c.Success:
            raise RuntimeError("Unknown Error Occurred: %i" % error_code)

        if self.py_value is None:
            ret.py_value = None
            ret.c_value = self.c_value ** power
        else:
            ret.py_value = self.py_value ** power

        return ret


    def __copy__(self):
        if self.py_value is None:
            return self

        cdef Quantity ret = Quantity.__new__(Quantity)
        ret.py_value = copy.copy(self.py_value)
        ret.udata = self.udata
        return ret

    def __deepcopy__(self, memodict={}):
        if self.py_value is None:
            return self

        cdef Quantity ret = Quantity.__new__(Quantity)
        ret.py_value = copy.deepcopy(self.py_value)
        ret.udata = self.udata
        return ret

    def __bool__(Quantity self):
        if self.py_value is None:
            return bool(self.c_value)
        return bool(self.py_value)


    def __float__(Quantity self):
        if self.py_value is None:
            return self.c_value
        return float(self.py_value)

    def __int__(Quantity self):
        if self.py_value is None:
            return int(self.c_value)
        return int(self.py_value)

    def __hash__(Quantity self):
        dims = tuple(self.udata.dimensions.exponents)
        if self.py_value is None:
            return hash((self.c_value * self.udata.scale, dims))
        return hash((self.py_value * self.udata.scale, dims))

    def __repr__(self):
        return 'Quantity(%r, %r)' % (self.quantity, self.units)