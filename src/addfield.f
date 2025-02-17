!> @file
!> @brief Pack up Sections 4 through 7 for a given field and add them
!> to a GRIB2 message.
!> @author Stephen Gilbert @date 2000-05-02

!> Pack up Sections 4 through 7 for a given field and add them to a
!> GRIB2 message.
!>
!> They are the Product Definition Section, Data Representation
!> Section, Bit-Map Section and Data Sections.
!>
!> This routine is used with routines gribcreate(), addlocal(),
!> addgrid(), and gribend() to create a complete GRIB2
!> message. Subroutine gribcreate() must be called first to initialize
!> a new GRIB2 message. Subroutine addgrid() must be called after
!> gribcreate() and before this routine to add the appropriate grid
!> description to the GRIB2 message. A call to gribend() is required
!> to complete GRIB2 message after all fields have been added.
!>
!> @param[inout] cgrib Character array to contain the GRIB2 message.
!> @param[in] lcgrib Maximum length (bytes) of array cgrib.
!> @param[in] ipdsnum Product Definition Template Number (see [Code
!> Table 4.0]
!> (https://www.nco.ncep.noaa.gov/pmb/docs/grib2/grib2_doc/grib2_table4-0.shtml)).
!> @param[in] ipdstmpl Contains the data values for the
!> Product Definition Template specified by ipdsnum.
!> @param[in] ipdstmplen Max dimension of ipdstmpl.
!> @param[out] coordlist Array containg floating point values intended to
!> document the vertical discretisation associated to model data on hybrid
!> coordinate vertical levels (part of Section 4).
!> @param[in] numcoord - number of values in array coordlist.
!> @param[in] idrsnum - Data Representation Template Number (see
!> [Code Table 5.0]
!> (https://www.nco.ncep.noaa.gov/pmb/docs/grib2/grib2_doc/grib2_table5-0.shtml)).
!> @param[in] idrstmpl Contains the data values for the Data
!> Representation Template specified by idrsnum. Note that some
!> values in this template (eg. reference values, number of bits,
!> etc...) may be changed by the data packing algorithms. Use this
!> to specify scaling factors and order of spatial differencing, if
!> desired.
!> @param[in] idrstmplen Max dimension of idrstmpl. This must be at
!> least as large as the length of the selected PDS template.
!> @param[in] fld Array of data points to pack.
!> @param[out] ngrdpts Number of data points in grid. i.e. size of
!> fld and bmap.
!> @param[out] ibmap Bitmap indicator (see [Code Table
!> 6.0](https://www.nco.ncep.noaa.gov/pmb/docs/grib2/grib2_doc/grib2_table6-0.shtml)).
!> - 0 bitmap applies and is included in Section 6.
!> - 1-253 Predefined bitmap applies
!> - 254 Previously defined bitmap applies to this field
!> - 255 Bit map does not apply to this product.
!> @param[out] bmap Logical*1 array containing bitmap to be added
!> (if ibmap=0 or ibmap=254).
!> @param[out] ierr Error return code.
!> - 0 no error.
!> - 1 GRIB message was not initialized. Need to call
!> routine gribcreate first.
!> - 2 GRIB message already complete. Cannot add new section.
!> - 3 Sum of Section byte counts does not add to total
!> byte count.
!> - 4 Previous Section was not 3 or 7.
!> - 5 Could not find requested Product Definition Template.
!> - 6 Section 3 (GDS) not previously defined in message.
!> - 7 Tried to use unsupported Data Representationi Template.
!> - 8 Specified use of a previously defined bitmap, but one
!> does not exist in the GRIB message.
!> - 9 GDT of one of 5.50 through 5.53 required to pack
!> using DRT 5.51.
!> - 10 Error packing data field.
!>
!> @author Stephen Gilbert @date 2000-05-02
      subroutine addfield(cgrib,lcgrib,ipdsnum,ipdstmpl,ipdstmplen,
     & coordlist,numcoord,idrsnum,idrstmpl,
     & idrstmplen,fld,ngrdpts,ibmap,bmap,ierr)
      use pdstemplates
      use drstemplates
      logical :: match
      character(len=1),intent(inout) :: cgrib(lcgrib)
      integer,intent(in) :: ipdsnum,ipdstmpl(*)
      integer,intent(in) :: idrsnum,numcoord,ipdstmplen,idrstmplen
      integer,intent(in) :: lcgrib,ngrdpts,ibmap
      real,intent(in) :: coordlist(numcoord)
      real(kind = 4) :: coordlist_4(numcoord)
      real,target,intent(in) :: fld(ngrdpts)
      integer,intent(out) :: ierr
      integer,intent(inout) :: idrstmpl(*)
      logical*1,intent(in) :: bmap(ngrdpts)

      character(len=4),parameter :: grib='GRIB',c7777='7777'
      character(len=4):: ctemp
      character(len=1),allocatable :: cpack(:)
      real,pointer,dimension(:) :: pfld
      real(4) :: coordieee(numcoord),re00
      integer(4) :: ire00,allones
      integer :: mappds(ipdstmplen),intbmap(ngrdpts),mapdrs(idrstmplen)
      integer,parameter :: zero=0,one=1,four=4,five=5,six=6,seven=7
      integer,parameter :: minsize=50000
      integer iofst,ibeg,lencurr,len,mappdslen,mapdrslen,lpos3
      integer width,height,ndpts
      integer lensec3,lensec4,lensec5,lensec6,lensec7
      logical issec3,needext,isprevbmap

      allones = int(Z'FFFFFFFF')
      ierr=0

!     Check to see if beginning of GRIB message exists
      match=.true.
      do i=1,4
         if(cgrib(i) /= grib(i:i)) then
            match=.false.
         endif
      enddo
      if (.not. match) then
        print *,'addfield: GRIB not found in given message.'
        print *,'addfield: Call to routine gribcreate required',
     & ' to initialize GRIB messge.'
        ierr=1
        return
      endif

!     Get current length of GRIB message
      call g2_gbytec(cgrib,lencurr,96,32)

!     Check to see if GRIB message is already complete
      ctemp=cgrib(lencurr-3)//cgrib(lencurr-2)//cgrib(lencurr-1)
     & //cgrib(lencurr)
      if (ctemp.eq.c7777) then
        print *,'addfield: GRIB message already complete.  Cannot',
     & ' add new section.'
        ierr=2
        return
      endif

!     Loop through all current sections of the GRIB message to
!     find the last section number.
      issec3=.false.
      isprevbmap=.false.
      len=16 ! length of Section 0
      do
      ! Get number and length of next section
        iofst=len*8
        call g2_gbytec(cgrib,ilen,iofst,32)
        iofst=iofst+32
        call g2_gbytec(cgrib,isecnum,iofst,8)
        iofst=iofst+8
      ! Check if previous Section 3 exists and save location of
      ! the section 3 in case needed later.
        if (isecnum.eq.3) then
           issec3=.true.
           lpos3=len+1
           lensec3=ilen
        endif
      ! Check if a previous defined bitmap exists
        if (isecnum.eq.6) then
          call g2_gbytec(cgrib,ibmprev,iofst,8)
          iofst=iofst+8
          if ((ibmprev.ge.0).and.(ibmprev.le.253)) isprevbmap=.true.
        endif
        len=len+ilen
      ! Exit loop if last section reached
        if (len.eq.lencurr) exit
      ! If byte count for each section does not match current
      ! total length, then there is a problem.
        if (len.gt.lencurr) then
          print *,'addfield: Section byte counts don''t add to total.'
          print *,'addfield: Sum of section byte counts = ',len
          print *,'addfield: Total byte count in Section 0 = ',lencurr
          ierr=3
          return
        endif
      enddo

!     Sections 4 through 7 can only be added after section 3 or 7.
      if ((isecnum.ne.3) .and. (isecnum.ne.7)) then
        print *,'addfield: Sections 4-7 can only be added after',
     & ' Section 3 or 7.'
        print *,'addfield: Section ',isecnum,' was the last found in',
     & ' given GRIB message.'
        ierr=4
        return

!     Sections 4 through 7 can only be added if section 3 was previously defined.
      elseif (.not.issec3) then
        print *,'addfield: Sections 4-7 can only be added if Section',
     & ' 3 was previously included.'
        print *,'addfield: Section 3 was not found in',
     & ' given GRIB message.'
        print *,'addfield: Call to routine addgrid required',
     & ' to specify Grid definition.'
        ierr=6
        return
      endif

!     Add Section 4 - Product Definition Section
      ibeg=lencurr*8 ! Calculate offset for beginning of section 4
      iofst=ibeg+32 ! leave space for length of section
      call g2_sbytec(cgrib,four,iofst,8) ! Store section number (4)
      iofst=iofst+8
      call g2_sbytec(cgrib,numcoord,iofst,16) ! Store num of coordinate values
      iofst=iofst+16
      call g2_sbytec(cgrib,ipdsnum,iofst,16) ! Store Prod Def Template num.
      iofst=iofst+16

      ! Get Product Definition Template
      call getpdstemplate(ipdsnum,mappdslen,mappds,needext,iret)
      if (iret.ne.0) then
        ierr=5
        return
      endif

      ! Extend the Product Definition Template, if necessary.
      ! The number of values in a specific template may vary
      ! depending on data specified in the "static" part of the
      ! template.
      if (needext) then
        call extpdstemplate(ipdsnum,ipdstmpl,mappdslen,mappds)
      endif

      ! Pack up each input value in array ipdstmpl into the
      ! the appropriate number of octets, which are specified in
      ! corresponding entries in array mappds.
      do i=1,mappdslen
        nbits=iabs(mappds(i))*8
        if ((mappds(i).ge.0).or.(ipdstmpl(i).ge.0)) then
          call g2_sbytec(cgrib,ipdstmpl(i),iofst,nbits)
        else
          call g2_sbytec(cgrib,one,iofst,1)
          call g2_sbytec(cgrib,iabs(ipdstmpl(i)),iofst+1,nbits-1)
        endif
        iofst=iofst+nbits
      enddo

      ! Add Optional list of vertical coordinate values
      ! after the Product Definition Template, if necessary.
      if (numcoord .ne. 0) then
         do i = 1, numcoord
            coordlist_4(i) = real(coordlist(i), 4)
         end do
        call mkieee(coordlist_4, coordieee, numcoord)
        call g2_sbytesc(cgrib,coordieee,iofst,32,0,numcoord)
        iofst=iofst+(32*numcoord)
      endif

      ! Calculate length of section 4 and store it in octets
      ! 1-4 of section 4.
      lensec4=(iofst-ibeg)/8
      call g2_sbytec(cgrib,lensec4,ibeg,32)

! Pack Data using appropriate algorithm

      ! Get Data Representation Template
      call getdrstemplate(idrsnum,mapdrslen,mapdrs,needext,iret)
      if (iret.ne.0) then
        ierr=5
        return
      endif

      ! contract data field, removing data at invalid grid points,
      ! if bit-map is provided with field.
      if (ibmap.eq.0 .OR. ibmap.eq.254) then
         allocate(pfld(max(2,ngrdpts)))
         ndpts=0;
         do jj=1,ngrdpts
             intbmap(jj)=0
             if (bmap(jj)) then
                intbmap(jj)=1
                ndpts=ndpts+1
                pfld(ndpts)=fld(jj);
             endif
         enddo
         if(ndpts==0 .and. ngrdpts>0) then
            pfld(1)=0
         endif
      else
         ndpts=ngrdpts;
         pfld=>fld;
      endif
      lcpack=0
      nsize=ndpts*4
      if (nsize .lt. minsize) nsize=minsize
      allocate(cpack(nsize),stat=istat)
      if (idrsnum.eq.0) then ! Simple Packing
        call simpack(pfld,ndpts,idrstmpl,cpack,lcpack)
      elseif (idrsnum.eq.2.or.idrsnum.eq.3) then ! Complex Packing
        call cmplxpack(pfld,ndpts,idrsnum,idrstmpl,cpack,lcpack)
      elseif (idrsnum.eq.50) then ! Sperical Harmonic Simple Packing
        call simpack(pfld(2),ndpts-1,idrstmpl,cpack,lcpack)
        call mkieee(real(pfld(1)),re00,1) ! ensure RE(0,0) value is IEEE format
        !call g2_gbytec(re00,idrstmpl(5),0,32)
        ire00=transfer(re00,ire00)
        idrstmpl(5)=ire00
      elseif (idrsnum.eq.51) then ! Sperical Harmonic Complex Packing
           call getpoly(cgrib(lpos3),lensec3,jj,kk,mm)
           if (jj.ne.0 .AND. kk.ne.0 .AND. mm.ne.0) then
             call specpack(pfld,ndpts,jj,kk,mm,idrstmpl,cpack,lcpack)
           else
             print *,'addfield: Cannot pack DRT 5.51.'
             ierr=9
             return
           endif

      elseif (idrsnum.eq.40 .OR. idrsnum.eq.40000) then ! JPEG2000 encoding
        if (ibmap.eq.255) then
           call getdim(cgrib(lpos3),lensec3,width,height,iscan)
           if (width.eq.0 .OR. height.eq.0) then
              width=ndpts
              height=1
           elseif (width.eq.allones .OR. height.eq.allones) then
              width=ndpts
              height=1
           elseif (ibits(iscan,5,1) .eq. 1) then ! Scanning mode: bit 3
              itemp=width
              width=height
              height=itemp
           endif
        else
           width=ndpts
           height=1
        endif
        if(width<1 .or. height<1) then
           ! Special case: bitmask off everywhere.
           write(0,*) 'Warning: bitmask off everywhere.'
           write(0,*) '   Pretend one point in jpcpack to avoid crash.'
           width=1
           height=1
        endif
        lcpack=nsize
        !print *,'w,h=',width,height
        call jpcpack(pfld,width,height,idrstmpl,cpack,lcpack)

      elseif (idrsnum.eq.41 .OR. idrsnum.eq.40010) then ! PNG encoding
        if (ibmap.eq.255) then
           call getdim(cgrib(lpos3),lensec3,width,height,iscan)
           if (width.eq.0 .OR. height.eq.0) then
              width=ndpts
              height=1
           elseif (width.eq.allones .OR. height.eq.allones) then
              width=ndpts
              height=1
           elseif (ibits(iscan,5,1) .eq. 1) then ! Scanning mode: bit 3
              itemp=width
              width=height
              height=itemp
           endif
        else
           width=ndpts
           height=1
        endif
        !print *,'png size ',width,height
        call pngpack(pfld,width,height,idrstmpl,cpack,lcpack)
        !print *,'png packed'
      else
        print *,'addfield: Data Representation Template 5.',idrsnum,
     * ' not yet implemented.'
        ierr=7
        return
      endif
      if (ibmap.eq.0 .OR. ibmap.eq.254) then
         deallocate(pfld)
      endif
      if (lcpack .lt. 0) then
        if(allocated(cpack))deallocate(cpack)
        ierr=10
        return
      endif

!     Add Section 5 - Data Representation Section
      ibeg=iofst ! Calculate offset for beginning of section 5
      iofst=ibeg+32 ! leave space for length of section
      call g2_sbytec(cgrib,five,iofst,8) ! Store section number (5)
      iofst=iofst+8
      call g2_sbytec(cgrib,ndpts,iofst,32) ! Store num of actual data points
      iofst=iofst+32
      call g2_sbytec(cgrib,idrsnum,iofst,16) ! Store Data Repr. Template num.
      iofst=iofst+16

      ! Pack up each input value in array idrstmpl into the
      ! the appropriate number of octets, which are specified in
      ! corresponding entries in array mapdrs.
      do i=1,mapdrslen
        nbits=iabs(mapdrs(i))*8
        if ((mapdrs(i).ge.0).or.(idrstmpl(i).ge.0)) then
          call g2_sbytec(cgrib,idrstmpl(i),iofst,nbits)
        else
          call g2_sbytec(cgrib,one,iofst,1)
          call g2_sbytec(cgrib,iabs(idrstmpl(i)),iofst+1,nbits-1)
        endif
        iofst=iofst+nbits
      enddo

      ! Calculate length of section 5 and store it in octets
      ! 1-4 of section 5.
      lensec5=(iofst-ibeg)/8
      call g2_sbytec(cgrib,lensec5,ibeg,32)

!     Add Section 6 - Bit-Map Section
      ibeg=iofst ! Calculate offset for beginning of section 6
      iofst=ibeg+32 ! leave space for length of section
      call g2_sbytec(cgrib,six,iofst,8) ! Store section number (6)
      iofst=iofst+8
      call g2_sbytec(cgrib,ibmap,iofst,8) ! Store Bit Map indicator
      iofst=iofst+8

      ! Store bitmap, if supplied
      if (ibmap.eq.0) then
        call g2_sbytesc(cgrib,intbmap,iofst,1,0,ngrdpts) ! Store BitMap
        iofst=iofst+ngrdpts
      endif

      ! If specifying a previously defined bit-map, make sure
      ! one already exists in the current GRIB message.
      if ((ibmap.eq.254).and.(.not.isprevbmap)) then
        print *,'addfield: Requested previously defined bitmap, ',
     & ' but one does not exist in the current GRIB message.'
        ierr=8
        return
      endif

      ! Calculate length of section 6 and store it in octets
      ! 1-4 of section 6. Pad to end of octect, if necessary.
      left=8-mod(iofst,8)
      if (left.ne.8) then
        call g2_sbytec(cgrib,zero,iofst,left) ! Pad with zeros to fill Octet
        iofst=iofst+left
      endif
      lensec6=(iofst-ibeg)/8
      call g2_sbytec(cgrib,lensec6,ibeg,32)

!     Add Section 7 - Data Section
      ibeg=iofst ! Calculate offset for beginning of section 7
      iofst=ibeg+32 ! leave space for length of section
      call g2_sbytec(cgrib,seven,iofst,8) ! Store section number (7)
      iofst=iofst+8
      ! Store Packed Binary Data values, if non-constant field
      if (lcpack.ne.0) then
        ioctet=iofst/8
        cgrib(ioctet+1:ioctet+lcpack)=cpack(1:lcpack)
        iofst=iofst+(8*lcpack)
      endif

      ! Calculate length of section 7 and store it in octets
      ! 1-4 of section 7.
      lensec7=(iofst-ibeg)/8
      call g2_sbytec(cgrib,lensec7,ibeg,32)

      if(allocated(cpack) )deallocate(cpack)

!     Update current byte total of message in Section 0
      newlen=lencurr+lensec4+lensec5+lensec6+lensec7
      call g2_sbytec(cgrib,newlen,96,32)

      return
      end
