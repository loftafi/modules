# Modules

The purpose of this repository is to make avaiable a public collection
of Biblical Greek resources and associated literature in a standardised
condensed binary format suitable for medium to high powered mobile
devices.

This github repository has two branches. The [master](https://github.com/loftafi/modules/tree/master/resources)
branch contains resources that have a licence that dedicates the resources
into the public domain. The [restricted](https://github.com/loftafi/modules/tree/restricted/resources)
branch contains resources with licenses that impose restrictions on reuse
and distribution such as the CC BY 4.0.

### Design

The module reader accepts a standardised set of token types (word, verse
marker, etc..) and outputs a standarised `.bin` file.

A custom tokenizer reads the data set and passes standardised tokens
into the module reader.

    Byzantine reader ---> Module --->  nestle.bin
       Nestle reader      reader       sbl.bin
          SBL reader                   byzantine.bin


### License

 - The code to build the binary files is public domain, under the MIT license.
 - For the data in each module, refer to the license information in each
    individual module `resource/`folder.

