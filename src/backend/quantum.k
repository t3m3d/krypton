module backend.quantum

quantum qpute(meas: qbit) -> bit {
    measure meas
}

quantum qpute_alloc() -> qbit {
    prepare qbit
}