#!/usr/bin/env python3
from __future__ import absolute_import, division, print_function, unicode_literals
import adios2
import argparse
from mpi4py import MPI
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
import decomp
import time
import os


def SetupArgs():
    parser = argparse.ArgumentParser()
    parser.add_argument("--instream", "-i", help="Name of the input stream", required=True)
    parser.add_argument("--outfile", "-o", help="Name of the output file", default="screen")
    parser.add_argument("--varname", "-v", help="Name of variable read", default="U")
    parser.add_argument("--nompi", "-nompi", help="ADIOS was installed without MPI", action="store_true")
    parser.add_argument("--displaysec", "-dsec", help="Float representing gap between plot window refresh", default=0.2)
    args = parser.parse_args()

    args.displaysec = float(args.displaysec)
    args.nx = 1
    args.ny = 1
    args.nz = 1

    return args


def PlotPDF(pdf, bins, args, start, count, step, fontsize):
    # Plotting part
    displaysec = args.displaysec
    gs = gridspec.GridSpec(1, 1)
    fig = plt.figure(1, figsize=(6,5))
    ax = fig.add_subplot(gs[0, 0])
    localSliceIdx = count[0] // 2
    globalSliceIdx = start[0] + localSliceIdx

    ax.plot(bins, pdf[localSliceIdx], 'r*-')
 
    ax.set_title("{0}, slice {1}, Timestep {2}".format(args.varname, globalSliceIdx, step), fontsize=fontsize)
    ax.set_xlabel("bins")
    ax.set_ylabel("count")
    plt.ion()
    if (args.outfile == "screen"):
        plt.show()
        plt.pause(displaysec)
    else:
        imgfile = args.outfile+"{0:0>3}".format(step)+"_" + str(globalSliceIdx) + ".png"
        fig.savefig(imgfile)

    plt.clf()


def read_data(args, fr, start_coord, size_dims):
    
    var1 = args.varname
    data= fr.read(var1, start_coord, size_dims )
    data = np.squeeze(data)
    return data


if __name__ == "__main__":
    # fontsize on plot
    fontsize = 22

    args = SetupArgs()
    # print(args)

    # Setup up 2D communicators if MPI is installed
    mpi = decomp.MPISetup(args)
    myrank = mpi.rank['world']
    
    # Read the data from this object
    fr = adios2.open(args.instream, "r", MPI.COMM_WORLD,"adios2.xml", "VizInput")


    # Read through the steps, one at a time
    for fr_step in fr:
        cur_step = fr_step.current_step()
        vars_info = fr_step.available_variables()
        # print (vars_info)
        pdfvar = args.varname+"/pdf"
        binvar = args.varname+"/bins"
        shape2_str = vars_info[pdfvar]["Shape"].split(',')
        shape2 = list(map(int,shape2_str))
        if myrank == 0:
            print("Step: {0}".format(cur_step))
            if cur_step == 0:
                print("Variable" + pdfvar + " shape is {" + vars_info[pdfvar]["Shape"]+"}")
        
        start = np.zeros(2, dtype=np.int64)
        count = np.zeros(2, dtype=np.int64)
        # Equally partition the PDF arrays among readers
        start[0], count[0] = decomp.Locate(myrank, mpi.size, shape2[0])
        start[1], count[1] = (0, shape2[1])
        start_bins = np.array([0], dtype=np.int64)
        count_bins = np.array([shape2[1]], dtype=np.int64)
        
        print("Rank {0} reads {1}  slices from offset {2}".format(myrank, count[0], start[0]))

        pdf = fr_step.read(pdfvar, start, count)
        bins = fr_step.read(binvar, start_bins, count_bins)

        PlotPDF (pdf, bins, args, start, count, cur_step, fontsize)
        
       
    fr.close()

