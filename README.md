# OpenKVI-bootcd
CentOS ISO file generation for an easy installation of OpenKVI.

### Getting the sources:
RPMs are stored with [Large File System] (https://git-lfs.github.com/) storage. 
So you need to install the [git-lfs client](https://packagecloud.io/github/git-lfs/install) and also use a git version that support hooks (> 1.8.0).  
First clone the repository with:
``` bash
> git clone https://github.com/louargantb/OpenKVI-bootcd.git
```
Then get RPMs from the LFS server:
``` bash
> cd OpenKVI-bootcd
> git lfs pull
```

### Building the ISO file:
Go to centos/7/centos/os/x86_64/tools/ directory and run `sh iso-tool.sh -p kvm`.  
For more options, check `sh iso-tool.sh -h`.
