module backend.quantum

quantum qpute_alloc() -> qbit {
    prepare qbit
}

quantum qpute(meas: qbit) -> bit {
    measure meas
}