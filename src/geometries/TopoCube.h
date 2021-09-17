/*  Copyright (c) 2011-2019 INGV, EDF, UniCT, JHU

    Istituto Nazionale di Geofisica e Vulcanologia, Sezione di Catania, Italy
    Électricité de France, Paris, France
    Università di Catania, Catania, Italy
    Johns Hopkins University, Baltimore (MD), USA

    This file is part of GPUSPH. Project founders:
        Alexis Hérault, Giuseppe Bilotta, Robert A. Dalrymple,
        Eugenio Rustico, Ciro Del Negro
    For a full list of authors and project partners, consult the logs
    and the project website <https://www.gpusph.org>

    GPUSPH is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    GPUSPH is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with GPUSPH.  If not, see <http://www.gnu.org/licenses/>.
 */
/*
 * File:   TopoCube.h
 * Author: alexis
 *
 * Created on 14 juin 2008, 18:04
 */

#ifndef _TOPOCUBE_H
#define	_TOPOCUBE_H

#include "Object.h"
#include "Point.h"
#include "Vector.h"

class TopoCube: public Object {
	private:
		Point	m_origin;
		Vector	m_vx, m_vy, m_vz;
		float*	m_dem;
		int		m_ncols, m_nrows;
		double	m_nsres, m_ewres;
		double	m_H;

		/* Geolocation data (optional) */
		double	m_north, m_south, m_east, m_west;
		double	m_voff; // vertical offset

	public:
		TopoCube(void);
		virtual ~TopoCube(void);

		/// return list of planes in implicit form as double4
		std::vector<double4> get_planes() const;

		void SetCubeDem(const float *dem,
				double sizex, double sizey, double H,
				int ncols, int nrows, double voff = 0);

		/* methods to retrieve the DEM geometry */
		int get_nrows()	{ return m_nrows; }
		int get_ncols()	{ return m_ncols; }
		double get_ewres()	{ return m_ewres; }
		double get_nsres()	{ return m_nsres; }
		double get_H()	{ return m_H; }
		Vector const& get_vx() { return m_vx; }
		Vector const& get_vy() { return m_vy; }
		Vector const& get_vz() { return m_vz; }

		/* allows direct read-only access to the DEM data */
		const float *get_dem() const { return m_dem; }

		void SetCubeHeight(double H);

		/* Geolocation data (optional) */
		void SetGeoLocation(double north, double south,
				double east, double west);

		double get_north()	{ return m_north; }
		double get_south()	{ return m_south; }
		double get_east()	{ return m_east; }
		double get_west()	{ return m_west; }
		double get_voff()	{ return m_voff; }

		//! Supported file formats
		enum Format {
			DEM_FMT_ASCII, /* GRASS ASCII grid format */
			DEM_FMT_VTK, /* VTK Structured Grid */
			DEM_FMT_XYZ /* XYZ file with header */
		};

		//! Load a topography from the file, given the file name and format
		//! \seealso TopoCube::Format
		static TopoCube* load_file(const char *fname, Format fmt);

		//! Format-specific implementation of topography loader
		template<Format>
		static TopoCube* load_file(const char *fname);

		/* Legacy loader names */
		static TopoCube* load_ascii_grid(const char *fname);
		static TopoCube* load_vtk_file(const char *fname);
		static TopoCube* load_xyz_file(const char *fname);

		using Object::SetPartMass;
		double SetPartMass(const double dx, const double rho) override;
		double Volume(const double dx) const override
		{
			return 0.0;
		}
		void SetInertia(const double dx) override
		{
			m_inertia[0] = 0.0;
			m_inertia[1] = 0.0;
			m_inertia[2] = 0.0;
		}

		void setEulerParameters(const EulerParameters &ep) override;
		void getBoundingBox(Point &output_min, Point &output_max) override;
		void shift(const double3 &offset) override;

		//! Fill a single face of the cube, optionally including its edges
		void FillBorder(PointVect&, const double dx, const int face_num, const bool fill_edges);

		void FillBorder(PointVect& points, const double dx) override
		{
			FillBorder(points, dx, 0, true);
			FillBorder(points, dx, 1, false);
			FillBorder(points, dx, 2, true);
			FillBorder(points, dx, 3, false);
		}

		void FillDem(PointVect&, const double);
		double DemInterpol(const double, const double) const;
		double DemDist(const double, const double, const double, const double) const;

		int Fill(PointVect&, const double, const double, const bool, const bool);
		int Fill(PointVect& points, const double H, const double dx, const bool faces_filled)
		{
			return Fill(points, H, dx, faces_filled, true);
		}
		int Fill(PointVect& points, const double dx, const bool fill = true) override
		{
			return Fill(points, m_H, dx, false, fill);
		}

		void FillIn(PointVect& points, const double dx, const int layers) override
		{ throw std::runtime_error("TopoCube::FillIn not implemented !"); }

		bool IsInside(const Point&, const double) const override;

};

#endif	/* _CUBE_H */

