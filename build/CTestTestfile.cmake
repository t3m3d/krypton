# CMake generated Testfile for 
# Source directory: C:/Users/brian/Documents/GitHub/krypton
# Build directory: C:/Users/brian/Documents/GitHub/krypton/build
# 
# This file includes the relevant testing commands required for 
# testing this directory and lists subdirectories to be tested as well.
if(CTEST_CONFIGURATION_TYPE MATCHES "^([Dd][Ee][Bb][Uu][Gg])$")
  add_test(krypton_tests "C:/Users/brian/Documents/GitHub/krypton/build/Debug/krypton_tests.exe")
  set_tests_properties(krypton_tests PROPERTIES  _BACKTRACE_TRIPLES "C:/Users/brian/Documents/GitHub/krypton/CMakeLists.txt;62;add_test;C:/Users/brian/Documents/GitHub/krypton/CMakeLists.txt;0;")
elseif(CTEST_CONFIGURATION_TYPE MATCHES "^([Rr][Ee][Ll][Ee][Aa][Ss][Ee])$")
  add_test(krypton_tests "C:/Users/brian/Documents/GitHub/krypton/build/Release/krypton_tests.exe")
  set_tests_properties(krypton_tests PROPERTIES  _BACKTRACE_TRIPLES "C:/Users/brian/Documents/GitHub/krypton/CMakeLists.txt;62;add_test;C:/Users/brian/Documents/GitHub/krypton/CMakeLists.txt;0;")
elseif(CTEST_CONFIGURATION_TYPE MATCHES "^([Mm][Ii][Nn][Ss][Ii][Zz][Ee][Rr][Ee][Ll])$")
  add_test(krypton_tests "C:/Users/brian/Documents/GitHub/krypton/build/MinSizeRel/krypton_tests.exe")
  set_tests_properties(krypton_tests PROPERTIES  _BACKTRACE_TRIPLES "C:/Users/brian/Documents/GitHub/krypton/CMakeLists.txt;62;add_test;C:/Users/brian/Documents/GitHub/krypton/CMakeLists.txt;0;")
elseif(CTEST_CONFIGURATION_TYPE MATCHES "^([Rr][Ee][Ll][Ww][Ii][Tt][Hh][Dd][Ee][Bb][Ii][Nn][Ff][Oo])$")
  add_test(krypton_tests "C:/Users/brian/Documents/GitHub/krypton/build/RelWithDebInfo/krypton_tests.exe")
  set_tests_properties(krypton_tests PROPERTIES  _BACKTRACE_TRIPLES "C:/Users/brian/Documents/GitHub/krypton/CMakeLists.txt;62;add_test;C:/Users/brian/Documents/GitHub/krypton/CMakeLists.txt;0;")
else()
  add_test(krypton_tests NOT_AVAILABLE)
endif()
